#include "common.hlsl"
 
 struct Input {
 	uint vertex_id : SV_VertexID;
 };
 
 struct Output {
 	float4 clip_position : SV_Position;
 	float3 texture_coords : TEXCOORD0;
 };
 
 Output main(Input input) {
 	//float2 vertices[] = {
 	//	float2(-1, -1),
 	//	float2( 3, -1),
 	//	float2(-1,  3),
 	//};
 	//float2 vertexPosition = vertices[input.vertexId];
 
 	// or the same without an array
 	float2 vertex_position = float2(
 		-1 + float((input.vertex_id & 1) << 2), // for vertex 0 and 2 we get -1 + 0, because bit 1 isn't set. for vertex 1 we get -1 + 4, because 1 << 2 is 4
 		-1 + float((input.vertex_id & 2) << 1) // for vertex 0 and 1 we get -1 + 0, because bit 2 isn't set. for vertex 2 we get -1 + 4, because 2 << 1 is 4
 	);
 
 	float4 clip_space_position = float4(vertex_position, 1, 1);
 
 	float4 view_space_position = mul(inverse_projection_matrix, clip_space_position);
 
 	float4 view_dir = mul(inverse_view_matrix, float4(view_space_position.xyz, 0));
 
 	Output output;
 	output.clip_position = clip_space_position;
 	output.texture_coords = view_dir;
 	return output;
 }