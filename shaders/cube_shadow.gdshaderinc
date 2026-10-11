vec3 cube_ray(int face, vec2 s) {
	if (face == 0) return normalize(vec3(1.0,-s.y,-s.x));
	if (face == 1) return normalize(vec3(-1.0,-s.y,s.x));
	if (face == 2) return normalize(vec3(s.x,1.0,s.y));
	if (face == 3) return normalize(vec3(s.x,-1.0,-s.y));
	if (face == 4) return normalize(vec3(s.x,-s.y,1.0));
	return normalize(vec3(-s.x,-s.y,-1.0));
}
vec3 cube_uv(vec3 d) {
	vec3 a = abs(d);
	if (a.x >= a.y && a.x >= a.z) return d.x>0.0 ? vec3(vec2(-d.z,-d.y)/a.x,0.0) : vec3(vec2(d.z,-d.y)/a.x,1.0);
	if (a.y >= a.z) return d.y>0.0 ? vec3(vec2(d.x,d.z)/a.y,2.0) : vec3(vec2(d.x,-d.z)/a.y,3.0);
	return d.z>0.0 ? vec3(vec2(d.x,-d.y)/a.z,4.0) : vec3(vec2(-d.x,-d.y)/a.z,5.0);
}
