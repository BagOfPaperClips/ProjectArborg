Shader "Custom/VerticalRevealLit"
{
    Properties
    {
        _BaseMap             ("Albedo (RGB)", 2D)                    = "white" {}
        _BaseColor           ("Color", Color)                        = (1, 1, 1, 1)
        _Smoothness          ("Smoothness", Range(0, 1))             = 0.5
        _Metallic            ("Metallic", Range(0, 1))               = 0.0
        _BumpMap             ("Normal Map", 2D)                      = "bump" {}
        _BumpScale           ("Normal Scale", Float)                 = 1.0
        _OcclusionMap        ("Occlusion", 2D)                       = "white" {}
        _OcclusionStrength   ("Occlusion Strength", Range(0,1))      = 1.0
        [HDR] _EmissionColor ("Emission Color", Color)               = (0,0,0,1)
        _EmissionMap         ("Emission Map", 2D)                    = "white" {}
        _Progress            ("Reveal Progress", Range(0, 1))        = 0
        _EdgeSoftness        ("Edge Softness", Range(0, 0.2))        = 0.05
        [HDR] _RevealGlowColor  ("Reveal Glow Color", Color)         = (0.3, 0.6, 1, 1)
        _RevealGlowWidth        ("Reveal Glow Width", Range(0,0.15)) = 0.04
        _RevealGlowStrength     ("Reveal Glow Strength", Range(0,5)) = 1.5
        _LocalYMin           ("Local Y Min", Float)                  = -0.5
        _LocalYMax           ("Local Y Max", Float)                  =  0.5
    }

    SubShader
    {
        Tags
        {
            "RenderPipeline"  = "UniversalPipeline"
            "Queue"           = "Transparent"
            "RenderType"      = "Transparent"
            "IgnoreProjector" = "True"
        }

        LOD 300

        // ============================================================
        //  Forward Lit
        // ============================================================
        Pass
        {
            Name "UniversalForward"
            Tags { "LightMode" = "UniversalForward" }

            Blend SrcAlpha OneMinusSrcAlpha
            ZWrite Off
            Cull Back

            HLSLPROGRAM
            #pragma vertex   vert
            #pragma fragment frag

            #pragma multi_compile _ _MAIN_LIGHT_SHADOWS _MAIN_LIGHT_SHADOWS_CASCADE
            #pragma multi_compile _ _ADDITIONAL_LIGHTS_VERTEX _ADDITIONAL_LIGHTS
            #pragma multi_compile _ _ADDITIONAL_LIGHT_SHADOWS
            #pragma multi_compile _ _SHADOWS_SOFT
            #pragma multi_compile_fog

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"
            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Lighting.hlsl"

            // --- Textures (declared manually — do NOT include SurfaceInput.hlsl
            //     as it re-declares _BaseMap and causes a redefinition error) ---
            TEXTURE2D(_BaseMap);      SAMPLER(sampler_BaseMap);
            TEXTURE2D(_BumpMap);      SAMPLER(sampler_BumpMap);
            TEXTURE2D(_OcclusionMap); SAMPLER(sampler_OcclusionMap);
            TEXTURE2D(_EmissionMap);  SAMPLER(sampler_EmissionMap);

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BumpMap_ST;
                float4 _OcclusionMap_ST;
                float4 _EmissionMap_ST;
                half4  _BaseColor;
                half   _Smoothness;
                half   _Metallic;
                float  _BumpScale;
                half   _OcclusionStrength;
                half4  _EmissionColor;
                float  _Progress;
                float  _EdgeSoftness;
                half4  _RevealGlowColor;
                float  _RevealGlowWidth;
                half   _RevealGlowStrength;
                float  _LocalYMin;
                float  _LocalYMax;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
                float4 tangentOS  : TANGENT;
                float2 uv         : TEXCOORD0;
                UNITY_VERTEX_INPUT_INSTANCE_ID
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float2 uv          : TEXCOORD0;
                float2 uvBump      : TEXCOORD1;
                float2 uvOcc       : TEXCOORD2;
                float2 uvEmission  : TEXCOORD3;
                float3 positionWS  : TEXCOORD4;
                float3 normalWS    : TEXCOORD5;
                float4 tangentWS   : TEXCOORD6;  // xyz=tangent, w=sign
                float  localY      : TEXCOORD7;
                float  fogFactor   : TEXCOORD8;
                UNITY_VERTEX_OUTPUT_STEREO
            };

            Varyings vert(Attributes IN)
            {
                Varyings OUT;
                UNITY_SETUP_INSTANCE_ID(IN);
                UNITY_INITIALIZE_VERTEX_OUTPUT_STEREO(OUT);

                VertexPositionInputs posInputs = GetVertexPositionInputs(IN.positionOS.xyz);
                VertexNormalInputs   nrmInputs = GetVertexNormalInputs(IN.normalOS, IN.tangentOS);

                OUT.positionHCS = posInputs.positionCS;
                OUT.positionWS  = posInputs.positionWS;
                OUT.normalWS    = nrmInputs.normalWS;
                OUT.tangentWS   = float4(nrmInputs.tangentWS, IN.tangentOS.w);

                OUT.uv         = TRANSFORM_TEX(IN.uv, _BaseMap);
                OUT.uvBump     = TRANSFORM_TEX(IN.uv, _BumpMap);
                OUT.uvOcc      = TRANSFORM_TEX(IN.uv, _OcclusionMap);
                OUT.uvEmission = TRANSFORM_TEX(IN.uv, _EmissionMap);

                OUT.localY     = IN.positionOS.y;   // object-space Y, rotation-invariant
                OUT.fogFactor  = ComputeFogFactor(posInputs.positionCS.z);
                return OUT;
            }

            half4 frag(Varyings IN) : SV_Target
            {
                // --- Reveal ------------------------------------------
                float range       = _LocalYMax - _LocalYMin;
                float normalizedY = saturate((IN.localY - _LocalYMin) / (range + 1e-5));
                float alpha = smoothstep(
                    _Progress + _EdgeSoftness,
                    _Progress - _EdgeSoftness,
                    normalizedY
                );
                clip(alpha - 0.001);

                // --- Albedo ------------------------------------------
                half4 albedo = SAMPLE_TEXTURE2D(_BaseMap, sampler_BaseMap, IN.uv) * _BaseColor;

                // --- Normal map --------------------------------------
                half4 normalSample = SAMPLE_TEXTURE2D(_BumpMap, sampler_BumpMap, IN.uvBump);
                half3 normalTS     = UnpackNormalScale(normalSample, _BumpScale);
                float3 bitangentWS = cross(IN.normalWS, IN.tangentWS.xyz) * IN.tangentWS.w;
                float3 normalWS    = TransformTangentToWorld(
                    normalTS,
                    half3x3(IN.tangentWS.xyz, bitangentWS, IN.normalWS)
                );
                normalWS = NormalizeNormalPerPixel(normalWS);

                // --- Lighting input ----------------------------------
                InputData lightData = (InputData)0;
                lightData.positionWS            = IN.positionWS;
                lightData.normalWS              = normalWS;
                lightData.viewDirectionWS       = GetWorldSpaceNormalizeViewDir(IN.positionWS);
                lightData.shadowCoord           = TransformWorldToShadowCoord(IN.positionWS);
                lightData.fogCoord              = IN.fogFactor;
                lightData.vertexLighting        = half3(0, 0, 0);
                lightData.bakedGI               = SampleSH(normalWS);
                lightData.normalizedScreenSpaceUV = GetNormalizedScreenSpaceUV(IN.positionHCS);
                lightData.shadowMask            = half4(1, 1, 1, 1);

                // --- Occlusion ---------------------------------------
                half occ = SAMPLE_TEXTURE2D(_OcclusionMap, sampler_OcclusionMap, IN.uvOcc).r;
                occ = lerp(1.0h, occ, _OcclusionStrength);

                // --- Emission + reveal glow --------------------------
                half3 baseEmit = SAMPLE_TEXTURE2D(_EmissionMap, sampler_EmissionMap, IN.uvEmission).rgb
                                 * _EmissionColor.rgb;
                float distToEdge = abs(normalizedY - _Progress);
                float edgeMask   = 1.0 - smoothstep(0.0, _RevealGlowWidth, distToEdge);
                edgeMask        *= step(normalizedY, _Progress + _RevealGlowWidth);

                // --- Surface data ------------------------------------
                SurfaceData surf = (SurfaceData)0;
                surf.albedo      = albedo.rgb;
                surf.metallic    = _Metallic;
                surf.smoothness  = _Smoothness;
                surf.normalTS    = normalTS;
                surf.occlusion   = occ;
                surf.emission    = baseEmit + _RevealGlowColor.rgb * (_RevealGlowStrength * edgeMask);
                surf.alpha       = albedo.a * alpha;
                surf.specular    = half3(0, 0, 0);

                half4 color = UniversalFragmentPBR(lightData, surf);
                color.rgb   = MixFog(color.rgb, IN.fogFactor);
                color.a     = surf.alpha;
                return color;
            }
            ENDHLSL
        }

        // ============================================================
        //  Shadow Caster
        //  Note: do NOT include Shadows.hlsl here — it depends on
        //  pipeline state not available in this pass and causes
        //  'LerpWhiteTo' undeclared errors. Use Core.hlsl only.
        // ============================================================
        Pass
        {
            Name "ShadowCaster"
            Tags { "LightMode" = "ShadowCaster" }

            ZWrite On
            ZTest LEqual
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   vertShadow
            #pragma fragment fragShadow
            #pragma multi_compile_shadowcaster

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            // _LightDirection is provided by URP's shadow rendering internals
            float3 _LightDirection;

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BumpMap_ST;
                float4 _OcclusionMap_ST;
                float4 _EmissionMap_ST;
                half4  _BaseColor;
                half   _Smoothness;
                half   _Metallic;
                float  _BumpScale;
                half   _OcclusionStrength;
                half4  _EmissionColor;
                float  _Progress;
                float  _EdgeSoftness;
                half4  _RevealGlowColor;
                float  _RevealGlowWidth;
                half   _RevealGlowStrength;
                float  _LocalYMin;
                float  _LocalYMax;
            CBUFFER_END

            struct Attributes
            {
                float4 positionOS : POSITION;
                float3 normalOS   : NORMAL;
            };

            struct Varyings
            {
                float4 positionHCS : SV_POSITION;
                float  localY      : TEXCOORD0;
            };

            Varyings vertShadow(Attributes IN)
            {
                Varyings OUT;
                float3 posWS  = TransformObjectToWorld(IN.positionOS.xyz);
                float3 nrmWS  = TransformObjectToWorldNormal(IN.normalOS);

                // Bias position along light direction to avoid shadow acne
                posWS = ApplyShadowBias(posWS, nrmWS, _LightDirection);

                OUT.positionHCS = TransformWorldToHClip(posWS);

                // Clamp depth for platforms with reversed Z
                #if UNITY_REVERSED_Z
                    OUT.positionHCS.z = min(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #else
                    OUT.positionHCS.z = max(OUT.positionHCS.z, OUT.positionHCS.w * UNITY_NEAR_CLIP_VALUE);
                #endif

                OUT.localY = IN.positionOS.y;
                return OUT;
            }

            half4 fragShadow(Varyings IN) : SV_Target
            {
                float range       = _LocalYMax - _LocalYMin;
                float normalizedY = saturate((IN.localY - _LocalYMin) / (range + 1e-5));
                float alpha = smoothstep(
                    _Progress + _EdgeSoftness,
                    _Progress - _EdgeSoftness,
                    normalizedY
                );
                clip(alpha - 0.01);
                return 0;
            }
            ENDHLSL
        }

        // ============================================================
        //  Depth Only (URP depth prepass — needed for SSAO etc.)
        // ============================================================
        Pass
        {
            Name "DepthOnly"
            Tags { "LightMode" = "DepthOnly" }

            ZWrite On
            ColorMask 0
            Cull Back

            HLSLPROGRAM
            #pragma vertex   vertDepth
            #pragma fragment fragDepth

            #include "Packages/com.unity.render-pipelines.universal/ShaderLibrary/Core.hlsl"

            CBUFFER_START(UnityPerMaterial)
                float4 _BaseMap_ST;
                float4 _BumpMap_ST;
                float4 _OcclusionMap_ST;
                float4 _EmissionMap_ST;
                half4  _BaseColor;
                half   _Smoothness;
                half   _Metallic;
                float  _BumpScale;
                half   _OcclusionStrength;
                half4  _EmissionColor;
                float  _Progress;
                float  _EdgeSoftness;
                half4  _RevealGlowColor;
                float  _RevealGlowWidth;
                half   _RevealGlowStrength;
                float  _LocalYMin;
                float  _LocalYMax;
            CBUFFER_END

            struct Attributes { float4 positionOS : POSITION; };
            struct Varyings   { float4 positionHCS : SV_POSITION; float localY : TEXCOORD0; };

            Varyings vertDepth(Attributes IN)
            {
                Varyings OUT;
                OUT.positionHCS = TransformObjectToHClip(IN.positionOS.xyz);
                OUT.localY      = IN.positionOS.y;
                return OUT;
            }

            half4 fragDepth(Varyings IN) : SV_Target
            {
                float range       = _LocalYMax - _LocalYMin;
                float normalizedY = saturate((IN.localY - _LocalYMin) / (range + 1e-5));
                float alpha = smoothstep(
                    _Progress + _EdgeSoftness,
                    _Progress - _EdgeSoftness,
                    normalizedY
                );
                clip(alpha - 0.01);
                return 0;
            }
            ENDHLSL
        }
    }

    FallBack "Universal Render Pipeline/Lit"
}
