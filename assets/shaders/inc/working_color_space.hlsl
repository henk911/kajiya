#ifndef WORKING_COLOR_SPACE_HLSL
#define WORKING_COLOR_SPACE_HLSL

#include "color.hlsl"

// ----

// Strong suppression; reduces noise in very difficult cases but introduces a lot of bias
float4 linear_rgb_to_crunched_luma_chroma(float4 v) {
    v.rgb = rgb_to_ycbcr(v.rgb);
    float k = sqrt(v.x) / max(1e-8, v.x);
    return float4(v.rgb * k, v.a);
}
float4 crunched_luma_chroma_to_linear_rgb(float4 v) {
    v.rgb *= v.x;
    v.rgb = ycbcr_to_rgb(v.rgb);
    return v;
}

// ----

float4 linear_rgb_to_crunched_rgb(float4 v) {
    return float4(sqrt(v.xyz), v.w);
}
float4 crunched_rgb_to_linear_rgb(float4 v) {
    return float4(v.xyz * v.xyz, v.w);
}

// ----

float4 linear_rgb_to_linear_luma_chroma(float4 v) {
    return float4(rgb_to_ycbcr(v.rgb), v.a);
}
float4 linear_luma_chroma_to_linear_rgb(float4 v) {
    return float4(ycbcr_to_rgb(v.rgb), v.a);
}

// ----

/*
TODO: consider this.
float4 linear_to_working(float4 v) {
    return log(1+sqrt(v));
}
float4 working_to_linear(float4 v) {
    v = exp(v) - 1.0;
    return v * v;
}*/

#endif  // WORKING_COLOR_SPACE_HLSL