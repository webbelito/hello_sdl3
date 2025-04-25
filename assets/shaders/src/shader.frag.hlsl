cbuffer Global : register(b0, space3) {
    float3 light_position;
    float3 light_color;
    float light_intensity;
}

struct Input {
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float3 position : TEXTCOORD2;
    float3 normal : TEXTCOORD3;
};

Texture2D<float4> texture : register(t0, space2);
SamplerState samp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
    
    // Get the base color from texture
    float4 base_color = texture.Sample(samp, input.uv);

    float3 vector_to_light = light_position - input.position;
    float distance_to_light = length(vector_to_light);
    float3 direction_to_light = vector_to_light / distance_to_light;

    float3 surface_normal = normalize(input.normal);

    float incidence_angle_factor = dot(direction_to_light, surface_normal); // 1 direct incidence, 0 no incidence, -1 incidence from the other side
    float3 reflected_radiance; 

    if (incidence_angle_factor > 0) {
        float attenuation_factor = 1 / (distance_to_light * distance_to_light); // TODO: Add more control variables
        float3 incoming_radiance = light_color * light_intensity;
        float3 irradiance = incoming_radiance * incidence_angle_factor * attenuation_factor;
        float3 brdf = 1; // TODO: Add more control variables

        reflected_radiance = irradiance * brdf;
    } else {
        reflected_radiance = float3(0, 0, 0);
    }

    float3 emitted_radiance = float3(0, 0, 0);
    float3 out_radiance = (emitted_radiance + reflected_radiance) * base_color.rgb;

    return float4(out_radiance, base_color.a);
}
