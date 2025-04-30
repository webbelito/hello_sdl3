cbuffer Global : register(b0, space3) {
    float3 light_position;
    float3 light_color;
    float light_intensity;
    float3 view_position;
    float3 ambient_light_color;
};

struct Input {

};

float4 main(Input input) : SV_Target0 {
    float3 out_radiance = light_color * light_intensity;
    return float4(out_radiance, 1.0);
}