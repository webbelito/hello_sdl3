cbuffer Global : register(b0, space1) {
    float4x4 view_projection_matrix;
};

cbuffer Local : register(b1, space1) {
    float4x4 model_matrix;
};

struct Import {
    float3 position : TEXCOORD0;
};

struct Output {
    float4 clip_position : SV_Position;
    float3 texture_coords : TEXCOORD0;
};

Output main(Import import) {

    float4 world_position = mul(model_matrix, float4(import.position, 1.0));

    Output output;
    output.clip_position = mul(view_projection_matrix, world_position);
    output.texture_coords = import.position;
    
    return output;
};
