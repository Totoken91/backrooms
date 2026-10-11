float traced_depth(vec3 origin, vec3 ray, float range_limit) {
	vec2 cell = floor((origin.xz - occ_origin) / occ_texel);
	vec2 step_dir = sign(ray.xz);
	vec2 safe_ray = mix(ray.xz, vec2(0.000001), lessThan(abs(ray.xz), vec2(0.000001)));
	vec2 boundary = occ_origin + (cell + max(step_dir, vec2(0.0))) * occ_texel;
	vec2 next_t = (boundary - origin.xz) / safe_ray;
	vec2 stride = abs(vec2(occ_texel) / safe_ray);
	next_t = mix(next_t, vec2(1e20), lessThan(abs(ray.xz), vec2(0.000001)));
	float t = 0.0;
	float hit = range_limit;
	for (int i = 0; i < 256; i++) {
		float end = min(min(next_t.x, next_t.y), range_limit);
		vec3 p = origin + ray * ((t + end) * 0.5);
		vec4 spans0, spans1;
		spans_at(p.xz, spans0, spans1);
		for (int k = 0; k < 4; k++) {
			vec2 slab = k == 0 ? spans0.xy : k == 1 ? spans0.zw : k == 2 ? spans1.xy : spans1.zw;
			if (slab.x < -50.0 && slab.y < -50.0) continue;
			if (abs(ray.y) < 0.000001) {
				if (origin.y > slab.x && origin.y < slab.y) hit = min(hit, t);
			} else {
				vec2 ys = (slab - origin.y) / ray.y;
				float enter = max(t, min(ys.x, ys.y));
				float leave = min(end, max(ys.x, ys.y));
				if (enter <= leave && leave >= 0.0) hit = min(hit, max(enter, 0.0));
			}
		}
		if (hit < range_limit) break;
		if (end >= range_limit) break;
		t = end;
		bool cross_x = next_t.x <= next_t.y;
		if (cross_x) next_t.x += stride.x;
		else next_t.y += stride.y;
	}
	return hit;
}
