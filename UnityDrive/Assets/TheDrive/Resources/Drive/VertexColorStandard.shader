Shader "TheDrive/VertexColorStandard" {
 Properties { _Color("Tint",Color)=(1,1,1,1) _Metallic("Metallic",Range(0,1))=0.2 _Glossiness("Smoothness",Range(0,1))=0.45 }
 SubShader { Tags { "RenderType"="Opaque" } LOD 200
 CGPROGRAM
 #pragma surface surf Standard fullforwardshadows vertex:vert
 #pragma target 3.0
 struct Input { float4 vertexColor; };
 fixed4 _Color; half _Metallic; half _Glossiness;
 void vert(inout appdata_full v, out Input o) { UNITY_INITIALIZE_OUTPUT(Input,o); o.vertexColor=v.color; }
 void surf(Input IN,inout SurfaceOutputStandard o) { o.Albedo=IN.vertexColor.rgb*_Color.rgb; o.Alpha=IN.vertexColor.a*_Color.a; o.Metallic=_Metallic; o.Smoothness=_Glossiness; }
 ENDCG
 } Fallback "Standard"
}
