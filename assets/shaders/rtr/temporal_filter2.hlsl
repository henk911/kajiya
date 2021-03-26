// TODO: currently a copy-pasta of the SSGI filter

#include "../inc/samplers.hlsl"
#include "../inc/uv.hlsl"
#include "../inc/frame_constants.hlsl"
#include "../inc/color.hlsl"

#define USE_DUAL_REPROJECTION 1

[[vk::binding(0)]] Texture2D<float4> input_tex;
[[vk::binding(1)]] Texture2D<float4> history_tex;
[[vk::binding(2)]] Texture2D<float> depth_tex;
[[vk::binding(3)]] Texture2D<float> ray_len_tex;
[[vk::binding(4)]] Texture2D<float4> reprojection_tex;
[[vk::binding(5)]] RWTexture2D<float4> output_tex;
[[vk::binding(6)]] cbuffer _ {
    float4 output_tex_size;
};

#define ENCODING_SCHEME 0

#if 0 == ENCODING_SCHEME
float4 linear_to_working(float4 x) {
    return sqrt(x);
}
float4 working_to_linear(float4 x) {
    return ((x)*(x));
}
#endif

#if 1 == ENCODING_SCHEME
float4 linear_to_working(float4 v) {
    return log(1+sqrt(v));
}
float4 working_to_linear(float4 v) {
    v = exp(v) - 1.0;
    return v * v;
}
#endif

#if 2 == ENCODING_SCHEME
float4 linear_to_working(float4 x) {
    return x;
}
float4 working_to_linear(float4 x) {
    return x;
}
#endif

#if 3 == ENCODING_SCHEME
float4 linear_to_working(float4 v) {
    return float4(ycbcr_to_rgb(v.rgb), v.a);
}
float4 working_to_linear(float4 v) {
    return float4(rgb_to_ycbcr(v.rgb), v.a);
}
#endif

#if 4 == ENCODING_SCHEME
float4 linear_to_working(float4 v) {
    v.rgb = sqrt(max(0.0, v.rgb));
    v.rgb = rgb_to_ycbcr(v.rgb);
    return v;
}
float4 working_to_linear(float4 v) {
    v.rgb = ycbcr_to_rgb(v.rgb);
    v.rgb *= v.rgb;
    return v;
}
#endif

[numthreads(8, 8, 1)]
void main(uint2 px: SV_DispatchThreadID) {
    #if 0
        output_tex[px] = float4(ray_len_tex[px].xxx * 0.1, 1);
        return;
    #elif 0
        output_tex[px] = input_tex[px];
        return;
    #endif

    const float4 center = linear_to_working(input_tex[px]);

    float refl_ray_length = clamp(ray_len_tex[px], 0, 1e3);

    // TODO: run a small edge-aware soft-min filter of ray length.
    // The `WaveActiveMin` below improves flat rough surfaces, but is not correct across discontinuities.
    //refl_ray_length = WaveActiveMin(refl_ray_length);
    
    float2 uv = get_uv(px, output_tex_size);
    
    const float center_depth = depth_tex[px];
    const ViewRayContext view_ray_context = ViewRayContext::from_uv_and_depth(uv, center_depth);
    const float3 reflector_vs = view_ray_context.ray_hit_vs();
    const float3 reflection_hit_vs = reflector_vs + view_ray_context.ray_dir_vs();

    const float4 reflection_hit_cs = mul(frame_constants.view_constants.view_to_sample, float4(reflection_hit_vs, 1));
    const float4 prev_hit_cs = mul(frame_constants.view_constants.clip_to_prev_clip, reflection_hit_cs);
    const float2 hit_prev_uv = cs_to_uv(prev_hit_cs.xy / prev_hit_cs.w);

    float4 reproj = reprojection_tex[px];

    float4 history0 = linear_to_working(history_tex.SampleLevel(sampler_lnc, uv + reproj.xy, 0));
    float history0_valid = 1;
    /*if (any(abs((uv + reproj.xy) * 2 - 1) > 0.99)) {
        history0_valid = 0;
    }*/

    float4 history1 = linear_to_working(history_tex.SampleLevel(sampler_lnc, hit_prev_uv, 0));
    float history1_valid = 1;
    /*if (any(abs(hit_prev_uv * 2 - 1) > 0.99)) {
        history1_valid = 0;
    }*/

    float4 history0_reproj = reprojection_tex.SampleLevel(sampler_lnc, uv + reproj.xy, 0);
    float4 history1_reproj = reprojection_tex.SampleLevel(sampler_lnc, hit_prev_uv, 0);

#if 1
	float4 vsum = 0.0.xxxx;
	float4 vsum2 = 0.0.xxxx;
	float wsum = 0.0;

	const int k = 1;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            const int2 sample_px = px + int2(x, y) * 1;
            const float sample_depth = depth_tex[sample_px];

            float4 neigh = linear_to_working(input_tex[sample_px]);
			float w = 1;//exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));

            w *= exp2(-200.0 * abs(/*center_normal_vs.z **/ (center_depth / sample_depth - 1.0)));

			vsum += neigh * w;
			vsum2 += neigh * neigh * w;
			wsum += w;
        }
    }

	float4 ex = vsum / wsum;
	float4 ex2 = vsum2 / wsum;
	//float4 dev = sqrt(max(0.0.xxxx, ex2 - ex * ex));
    //float4 dev = sqrt(max(0.1 * ex, ex2 - ex * ex));
    float4 dev = sqrt(max(0.0.xxxx, ex2 - ex * ex));
    //dev = max(dev, 0.1);

    float reproj_validity_dilated = reproj.z;
    /*#if 1
        {
         	const int k = 2;
            for (int y = -k; y <= k; ++y) {
                for (int x = -k; x <= k; ++x) {
                    reproj_validity_dilated = min(reproj_validity_dilated, reprojection_tex[px + 2 * int2(x, y)].z);
                }
            }
        }
    #else
        reproj_validity_dilated = min(reproj_validity_dilated, WaveReadLaneAt(reproj_validity_dilated, WaveGetLaneIndex() ^ 1));
        reproj_validity_dilated = min(reproj_validity_dilated, WaveReadLaneAt(reproj_validity_dilated, WaveGetLaneIndex() ^ 8));
    #endif*/

    float box_size = 1;
    const float n_deviations = 2.5 * lerp(2.0, 0.5, saturate(length(reproj.xy))) * reproj_validity_dilated;
	//float4 nmin = lerp(center, ex, box_size * box_size) - dev * box_size * n_deviations;
	//float4 nmax = lerp(center, ex, box_size * box_size) + dev * box_size * n_deviations;
	float4 nmin = center - dev * box_size * n_deviations;
	float4 nmax = center + dev * box_size * n_deviations;
#else
	float4 vsum = 0.0.xxxx;
	float wsum = 0.0;

    float4 nmin = center;
    float4 nmax = center;

	const int k = 2;
    for (int y = -k; y <= k; ++y) {
        for (int x = -k; x <= k; ++x) {
            float4 neigh = linear_to_working(input_tex[px + int2(x, y) * 1]);
			nmin = min(nmin, neigh);
            nmax = max(nmax, neigh);

			float w = exp(-3.0 * float(x * x + y * y) / float((k+1.) * (k+1.)));
			vsum += neigh * w;
			wsum += w;
        }
    }
    
    float4 ex = vsum / wsum;
#endif
    
    float h0diff = length(history0.xyz - center.xyz);
    float h1diff = length(history1.xyz - center.xyz);
    float hdiff_scl = max(1e-10, max(h0diff, h1diff));

#if USE_DUAL_REPROJECTION
    float h0_score = exp2(-100 * min(1, h0diff / hdiff_scl)) * history0_valid;
    float h1_score = exp2(-100 * min(1, h1diff / hdiff_scl)) * history1_valid;
#else
    float h0_score = 1;
    float h1_score = 0;
#endif

    //const float reproj_penalty = 1000;
    //history0 = lerp(center, history0, exp2(-reproj_penalty * length(history0_reproj.xy - reproj.xy)));
    //history1 = lerp(center, history1, exp2(-reproj_penalty * length(history1_reproj.xy - reproj.xy)));

    const float score_sum = h0_score + h1_score;
    if (score_sum > 1e-50) {
        h0_score /= score_sum;
        h1_score /= score_sum;
    } else {
        h0_score = 1;
        h1_score = 0;
    }

    float4 clamped_history0 = clamp(history0, nmin, nmax);
    float4 clamped_history1 = clamp(history1, nmin, nmax);
    //float4 clamped_history = clamp(history0 * h0_score + history1 * h1_score, nmin, nmax);
    float4 clamped_history = clamped_history0 * h0_score + clamped_history1 * h1_score;
    //float4 clamped_history = history0 * h0_score + history1 * h1_score;

    //float sample_count = history0.w * h0_score + history1.w * h1_score;
    //sample_count *= reproj.z;

    //clamped_history = lerp(center, clamped_history, reproj.z);
    //clamped_history = center;

    //clamped_history = history0;
    //clamped_history.w = history0.w;

    float target_sample_count = 16;//lerp(8, 24, saturate(0.3 * center.w));
    //float target_sample_count = 24;//lerp(8, 24, saturate(0.3 * center.w));
    //float target_sample_count = clamp(sample_count, 1, 24);//lerp(8, 24, saturate(0.3 * center.w));

    //float4 filtered_center = lerp(center, ex, saturate(clamped_history.w * 5));
    float4 filtered_center = center;
    float4 res = lerp(clamped_history, filtered_center, lerp(1.0, 1.0 / target_sample_count, reproj_validity_dilated));
    //res.w = sample_count + 1;
    //res.w = refl_ray_length * 20;

    //res.rgb = working_to_linear(dev).rgb / max(1e-8, working_to_linear(ex).rgb);
    res = working_to_linear(res);
    //res.rgb = working_to_linear(center).rgb * res.w * 0.01;

    //res.w = calculate_luma(working_to_linear(dev).rgb / max(1e-5, working_to_linear(ex).rgb));
    
    output_tex[px] = max(0.0.xxxx, res);
    //output_tex[px].w = h0_score / (h0_score + h1_score);
    //output_tex[px] = reproj.w;
}