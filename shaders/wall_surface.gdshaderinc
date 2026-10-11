// Reconstruct each sample in its own vertical space BEFORE interpolation.
// Mixing heights from two rooms and interpreting them using a nearest gap
// creates a hard cut on a continuous wall at a ceiling boundary.
float wall_surface_tap(vec2 chunk, ivec2 p, ivec2 res, int owner, int axis, float y, float emax, float default_ceiling) {
	int first = axis == 3 ? 1 : 0;
	int channel = axis == 3 ? 0 : axis + 1;
	vec4 a = chunk_tap(light_maps, MAPS, first, chunk, p, res, owner);
	vec4 b = chunk_tap(light_maps, MAPS, first+1, chunk, p, res, owner);
	vec4 c = chunk_tap(light_maps, MAPS, first+2, chunk, p, res, owner);
	vec4 packed = chunk_tap(light_maps, MAPS, 4, chunk, p, res, owner);
	vec2 gap = vec2(decode_height(packed.xy),decode_height(packed.zw));
	vec2 point = chunk * CHUNK_SIZE + (vec2(p)+0.5)/vec2(res)*CHUNK_SIZE;
	float emitter = max(gap.y,structural_ceiling(point,default_ceiling))-0.01;
	return wall_profile(a[channel]*a[channel]*emax,b[channel]*b[channel]*emax,c[channel]*c[channel]*emax,y,gap,emitter);
}
float wall_surface_light(vec2 at, int axis, float y, float emax, float default_ceiling) {
	vec2 uv;
	int owner = light_slot(at,uv);
	if (owner < 0) return 0.0;
	ivec2 res = textureSize(light_maps,0).xy;
	vec2 pixel = uv*vec2(res)-0.5;
	ivec2 p = ivec2(floor(pixel));
	vec2 f = fract(pixel);
	vec2 chunk = floor(at/CHUNK_SIZE);
	float a = wall_surface_tap(chunk,p,res,owner,axis,y,emax,default_ceiling);
	float b = wall_surface_tap(chunk,p+ivec2(1,0),res,owner,axis,y,emax,default_ceiling);
	float c = wall_surface_tap(chunk,p+ivec2(0,1),res,owner,axis,y,emax,default_ceiling);
	float d = wall_surface_tap(chunk,p+ivec2(1,1),res,owner,axis,y,emax,default_ceiling);
	return mix(mix(a,b,f.x),mix(c,d,f.x),f.y);
}
