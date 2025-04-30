#include "common.hlsl"

cbuffer Local : register(b1, space1) {
    float4x4 model_matrix;
};

struct Input {
    float3 position : TEXCOORD0;
};

struct Output {
    float4 clip_position : SV_POSITION;
};

Output main(Input input) {
    float4 world_position = mul(model_matrix, float4(input.position, 1.0));

    Output output;
    output.clip_position = mul(view_projection_matrix, world_position);
    return output;
}
