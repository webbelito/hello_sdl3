cbuffer Global : register(b0, space1) {
    float4x4 view_projection_matrix;
}

cbuffer Local : register(b1, space1) {
    float4x4 model_matrix;
    float4x4 normal_matrix;
}


struct Input {
    float3 position : TEXCOORD0;
    float4 color : TEXCOORD1;
    float2 uv : TEXCOORD2;
    float3 normal : TEXCOORD3;
};

struct Output {
    float4 clip_position : SV_Position;
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float3 position : TEXTCOORD2;
    float3 normal : TEXTCOORD3;
};

Output main(Input input) {

    float4 world_position = mul(model_matrix, float4(input.position, 1));

    Output output;
    output.clip_position = mul(view_projection_matrix, world_position);
    output.color = input.color;
    output.uv = input.uv;
    output.position = world_position.xyz;
    output.normal = normalize(mul(normal_matrix, float4(input.normal, 0)).xyz); 
    return output;
}
