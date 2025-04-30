#include "common.hlsl"

struct Input {

};

float4 main(Input input) : SV_Target0 {
    float3 out_radiance = light_color * light_intensity;
    return float4(out_radiance, 1.0);
}