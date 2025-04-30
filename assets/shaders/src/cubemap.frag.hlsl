struct Import {
    float3 texture_coords: TEXCOORD0;
};

TextureCube<float4> cubemap_texture: register(t0, space2);
SamplerState cubemap_sampler: register(s0, space2);

float4 main(Import import) : SV_Target0 {
    return cubemap_texture.Sample(cubemap_sampler, import.texture_coords);
};


