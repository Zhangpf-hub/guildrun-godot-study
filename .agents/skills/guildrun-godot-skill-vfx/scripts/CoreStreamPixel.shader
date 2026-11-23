Shader "Hidden/CoreStreamPixel"
{
    SubShader
    {
        Tags { "Queue" = "Transparent" }
        Pass
        {
            Cull Off
            ZWrite Off
            HLSLPROGRAM
            #pragma vertex vert
            #pragma fragment frag
            #include "UnityCG.cginc"

            struct Attributes
            {
                float4 position : POSITION;
                float4 texcoord0 : TEXCOORD0;
                float4 texcoord1 : TEXCOORD1;
            };

            struct Interpolants
            {
                float4 position : SV_POSITION;
                float3 lanes : TEXCOORD0;
            };

            Interpolants vert(Attributes input)
            {
                Interpolants output;
                output.position = UnityObjectToClipPos(input.position);
                output.lanes = float3(input.texcoord0.z, input.texcoord1.zw);
                return output;
            }

            float4 frag(Interpolants input) : SV_Target
            {
                return float4(input.lanes, 1.0);
            }
            ENDHLSL
        }
    }
}
