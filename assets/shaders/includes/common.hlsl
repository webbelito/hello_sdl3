#if __SHADER_TARGET_STAGE == __SHADER_STAGE_VERTEX

cbuffer Global : register(b0, space1) {
    float4x4 view_projection_matrix;
    float4x4 inverse_view_matrix;
    float4x4 inverse_projection_matrix;
};

#elif __SHADER_TARGET_STAGE == __SHADER_STAGE_PIXEL

cbuffer Global : register(b0, space3) {
    float3 light_position;
    float3 light_color;
    float light_intensity;
    float3 view_position;
    float3 ambient_light_color;
};

#endif