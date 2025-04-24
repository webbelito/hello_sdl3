struct Input {
    float4 color : TEXCOORD0;
    float2 uv : TEXCOORD1;
};

Texture2D<float4> texture : register(t0, space2);
SamplerState samp : register(s0, space2);

float4 main(Input input) : SV_Target0 {
    
    // * Gamma Correction
    float4 color = texture.Sample(samp, input.uv);

    // TODO: Here the colors are linear

    // * Apply Color
    float4 finalColor = color * input.color;

    return finalColor;
}
