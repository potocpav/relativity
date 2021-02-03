#define PI 3.1416

varying vec2 v_texcoord;
uniform float time;
uniform float c;
uniform vec2 r0_ship;
uniform vec2 origin_r;
uniform vec2 origin_u;
uniform sampler1D r_ship;
uniform sampler1D u_ship;
uniform float time_span;
uniform vec4 thursters;
uniform float doppler;
uniform float view_w;
uniform vec2 view_offset;

uniform sampler2D earth_tex;
uniform sampler2D self_tex;

// Color blending function
vec4 overlay(vec4 c1, vec4 c2) {
    vec3 ca = c1.rgb * c1.a;
    vec3 cb = c2.rgb * c2.a;
    vec3 co = ca + cb * (1.0 - c1.a);
    return vec4(co, c1.a + c2.a * (1 - c1.a));
}

float gamma_f(vec2 u) {
    return pow(1.0 - pow(length(u) / c, 2.0), -0.5);
}

vec3 u_four(vec2 u) {
    float g = gamma_f(u);
    return vec3(g * c, g * u);
}

vec3 lorentz(vec3 r, vec3 u) {
    float gamma = u.x / c;
    vec2 v = u.yz / gamma;
    vec2 n = normalize(v); // FIXME: handle zero `u`
    float t = gamma * (r.x - length(v) * dot(n, r.yz) / c);
    vec2 a = r.yz + (gamma - 1) * dot(n, r.yz) * n - gamma * r.x * length(v) * n / c;
    return vec3(t, a);
}

vec3 inv_lorentz(vec3 r, vec3 u) {
    float gamma = u.x / c;
    vec2 v = u.yz / gamma;
    vec2 n = normalize(v); // FIXME: handle zero `u`
    float t = gamma * (r.x + length(v) * dot(n, r.yz) / c);
    vec2 a = r.yz + (gamma - 1) * dot(n, r.yz) * n + gamma * r.x * length(v) * n / c;
    return vec3(t, a);
}

float find_simul(sampler1D rr, sampler1D uu, vec3 pt) {
    float i = 0.5;
    float di = 0.25;
    for (int n = 0; n < 20; n++) {
        vec3 r = texture1D(rr, i).xyz;
        vec3 u = texture1D(uu, i).xyz;
        vec3 d = pt - r;

        i += lorentz(d, u).x > 0 ? di : -di;
        di /= 2;
    }
    return i;
}

vec4 photon_clock(float t, vec2 r, float size) {
    float pt_size = size / 5.0;
    float p = abs(mod(c * t, size * 4) - size * 2) - size;
    vec2 pos1 = vec2(p, 0.0);
    vec2 pos2 = vec2(0.0, p);
    float fac1 = max(0.0, 1.0 - length(pos1 - r) / pt_size);
    float fac2 = max(0.0, 1.0 - length(pos2 - r) / pt_size);

    float s = size;
    float borders = abs(max(abs(r.x), abs(r.y)) - size) < pt_size / 4.0 ? 1.0 : 0.0;

    float tick = mod(t, 1.0) < 0.1 ? 1.0 : 0.0;
    float close = (abs(r.x) < size) && (abs(r.y) < size) ? 1.0 : 0.0;
    float fill = tick * close * 0.2;

    return vec4(1.0, 1.0, 0.0, fill + max(borders, max(fac1, fac2)));
}

vec4 ship(float t, vec2 r, float size) {
    float close = (abs(r.x) < size) && (abs(r.y) < size) ? 1.0 : 0.0;
    float flame_size = 0.1;

    float th_up = exp(-length(r - vec2(0.0, size * 1.1)) / flame_size) * thursters.x;
    float th_dn = exp(-length(r - vec2(0.0, -size * 1.1)) / flame_size) * thursters.z;
    float th_le = exp(-length(r - vec2(-size * 1.1, 0.0)) / flame_size) * thursters.y;
    float th_ri = exp(-length(r - vec2(size * 1.1, 0.0)) / flame_size) * thursters.w;

    vec4 c_thursters =
        vec4(vec3(1.0, 1.0, 0.6), th_up + th_dn + th_le + th_ri);
    return overlay(close * texture2D(self_tex, r / size / 2.0 + 0.5), c_thursters);
}

vec4 background(float t, vec2 r) {
    float stride = 1.0, thickness = 0.02;
    float tick = 1.0;
    float alpha = mod(t, tick) < tick / 10.0 ? 0.25 : 0.2;
    float major =
        (mod(r.x, stride) < thickness) ||
        (mod(r.y, stride) < thickness) ? 1.0 : 0.0;
    float minor =
        (mod(r.x, stride * 0.2) < thickness * 0.5) ||
        (mod(r.y, stride * 0.2) < thickness * 0.5) ? 0.5 : 0.0;
    float axes =
        ((r.x > 0.0) && (r.x < thickness * 1.0)) ||
        ((r.y > 0.0) && (r.y < thickness * 1.0)) ? 2.0 : 0.0;

    // vec2 r_ray = vec2(mod(c * t, 3.0), 0.0);

    return vec4(vec3(max(max(major, minor), axes) * alpha), 1.0);
}

vec4 earth(float t, vec2 r) {
    float T = time_span;
    float phi = t * 2.0 * PI / T;
    mat2 m = mat2(cos(phi), sin(phi), -sin(phi), cos(phi));
    vec2 rr = m * r;
    return length(r) < 0.5 ? texture2D(earth_tex, rr + 0.5) : vec4(0.0);
    // return length(r) < 0.5 ? vec4(1.0) : vec4(0.0);
}

void main() {
    float t = mod(time, time_span);
    vec3 o_r = vec3(t * c, origin_r);
    vec3 o_u = u_four(origin_u);

    vec2 view1 = v_texcoord - vec2(0.0, 0.0);
    vec2 view2 = v_texcoord - o_r.yz / 7.0;
    // vec2 view = v_texcoord.x > 0.5 ? view1 : view2;
    vec2 pt_o = (view1 * 2.0 - 1.0 + view_offset) * view_w;
    vec3 pt3_o = vec3(0.0 - length(pt_o) * doppler, pt_o);
    vec3 pt3 = inv_lorentz(pt3_o, o_u) + o_r;

    float i = find_simul(r_ship, u_ship, pt3);
    vec3 r = texture1D(r_ship, i).xyz;
    vec3 u = texture1D(u_ship, i).xyz;

    vec3 r_ship = lorentz(pt3 - r, u);
    // float gamma_ship = u.x / c;
    vec4 c_ship = photon_clock(i * time_span, r_ship.yz, c / 8.0);
    vec4 bg = background(pt3.x / c, pt3.yz);
    vec4 self = ship(t, pt_o, 0.2);
    vec4 earth_ = earth(pt3.x / c, pt3.yz);
    gl_FragColor = overlay(overlay(self, c_ship), overlay(earth_, bg));
}