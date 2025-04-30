/*cbuffer Global : register(b0, space3) {
    float3 light_position;
    float3 light_color;
    float light_intensity;
    float3 view_position;
    float3 ambient_light_color;
}
*/

#include "common.hlsl"
cbuffer Local : register(b1, space3) {
    float3 material_specular_color;
    float material_shininess;
}

struct Input {
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
    float3 position : TEXTCOORD2;
    float3 normal : TEXTCOORD3;
};

Texture2D<float4> diffuse_map : register(t0, space2);
SamplerState samp : register(s0, space2);

float3 blinnPhongBRDF(float3 direction_to_light, float3 direction_to_view, float3 surface_normal, float3 material_diffuse_reflection) {

    float3 halfway_direction = normalize(direction_to_light + direction_to_view);
    float specular_dot = max(0, dot(halfway_direction, surface_normal));
    float specular_factor = pow(specular_dot, material_shininess);
    float3 specular_reflection = material_specular_color * specular_factor;

    return material_diffuse_reflection + specular_reflection; // TODO: Energy conservation / normalization

}

float4 main(Input input) : SV_Target0 {
    
    float3 vector_to_light = light_position - input.position;
    float distance_to_light = length(vector_to_light);
    float3 direction_to_light = vector_to_light / distance_to_light;

    float3 direction_to_view = normalize(view_position - input.position);

    float3 surface_normal = normalize(input.normal);

    float3 material_diffuse_reflection = diffuse_map.Sample(samp, input.uv).rgb;

    float3 ambient_irradiance = ambient_light_color;

    float3 reflected_radiance = ambient_irradiance * material_diffuse_reflection;

    float incidence_angle_factor = dot(direction_to_light, surface_normal); // 1 direct incidence, 0 no incidence, -1 incidence from the other side

    if (incidence_angle_factor > 0) {
        float attenuation_factor = 1 / (distance_to_light * distance_to_light); // TODO: Add more control variables
        float3 incoming_radiance = light_color * light_intensity;
        float3 irradiance = incoming_radiance * incidence_angle_factor * attenuation_factor;
        float3 brdf = blinnPhongBRDF(direction_to_light, direction_to_view, surface_normal, material_diffuse_reflection);
        reflected_radiance += irradiance * brdf;
    }

    float3 emitted_radiance = float3(0, 0, 0);
    float3 out_radiance = emitted_radiance + reflected_radiance;

    return float4(out_radiance, 1);
}
