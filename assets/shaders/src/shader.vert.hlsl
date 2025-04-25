cbuffer UBO : register(b0, space1) { // TODO: Separate global and local UBOs
    float4x4 view_projection;
    float4x4 material;
};

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

    float4 world_position = mul(material, float4(input.position, 1));

    Output output;
    output.clip_position = mul(view_projection, world_position);
    output.color = input.color;
    output.uv = input.uv;
    output.position = world_position.xyz;
    output.normal = normalize(mul(material, float4(input.normal, 0)).xyz); // TODO: use normal matrix to support non-uniform scales
    return output;
}
