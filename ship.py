#!/usr/bin/env python3

import numpy as np
from glumpy import app, gl, glm, gloo, __version__
from glumpy.transforms import PanZoom, Position, Viewport
from PIL import Image
from collections import deque

def f_ship(t_ship):
    t = t_ship % 8
    res = np.zeros((len(t_ship), 2))
    res[t < 1, 0] = 4.0
    res[(1 <= t) & (t < 3), 0] = -4.0
    res[(3 <= t) & (t < 4), 0] = 4.0
    return res

def interpolate(t, tt, rr):
    t = t % tt[-1]
    i0 = np.searchsorted(tt, t, 'right') - 1
    i1 = i0 + 1
    t0, t1 = tt[i0], tt[i1]
    fac = (t - t0) / (t1 - t0)
    return fac * rr[i1] + (1 - fac) * rr[i0]

def f_to_a(f, m, uuu, c):
    gamma = uuu[0] / c
    u = uuu[1:] / gamma
    return 1 / (gamma * m) * (f - (f * u).sum() * u / c ** 2)

def u_to_four(u, c):
    gamma = (1.0 - ((u / c) ** 2).sum()) ** (-0.5)
    return gamma * np.array([c, u[0], u[1]])

def from_proper4(tt_proper, ff_proper, c, u0=None, mass=1):
    dt_proper = tt_proper[1] - tt_proper[0]
    t0 = 0.0
    if u0 is None:
        u0 = np.array([c, 0, 0], 'f8')
    else:
        u0 = np.array(u0, 'f8')

    tt = np.empty_like(tt_proper)
    uu = np.empty((len(tt_proper), 3), 'f8')
    aa = np.empty((len(tt_proper), 3), 'f8')

    for i, (t, f) in enumerate(zip(tt_proper, ff_proper)):
        gamma = u0[0] / c
        u0n = u0[1:] / gamma
        u_sq = np.sum(u0n ** 2)

        # a0 = 1 / (gamma * mass) * (f - (f * u0n).sum() * u0n / c ** 2)
        a0 = f_to_a(f, mass, u0, c)
        dot = (a0 * u0n).sum()
        a = np.append(
            gamma ** 4 * dot / c,
            gamma ** 4 * dot * u0n / c ** 2 + gamma ** 2 * a0
            )
        u0 += a * dt_proper

        aa[i] = a
        uu[i] = u0

        norm_factor = (u0[0] ** 2 - (u0[1:] ** 2).sum()) / c ** 2
        u0 /= norm_factor
    return tt, uu, aa

# %%

c = 3.0

dt = 1/60
tt_ship = deque()
tt_ship.push(0.0)
ff_ship = np.zeros(2.0)

tt0_ship, uuu_ship, aa0_ship = from_proper4(tt_ship, ff_ship, c)

rrr = np.cumsum(uuu_ship, axis=0) * dt + [0, -2.0, -1.5]
tt0_ship, rr0_ship = rrr[:, 0] / c, rrr[:, 1:]


r0_ship = lambda t: interpolate(t, tt0_ship, rr0_ship)

tt0_obsv, aa0_obsv = tt0_ship, aa0_ship

window = app.Window(width=1024, height=1024)
t_glob = 0.0
doppler = 0.0
view_w = 3.5
view_offset = np.array([0.0, 0.0])

origin_r = np.array([0.5, 0.5])
origin_u = np.array([0.0, 1e-5])
key_up, key_dn, key_le, key_ri = False, False, False, False

@window.event
def on_draw(dt):
    global t_glob, origin_u, origin_r
    window.clear()
    t_glob += dt
    f = np.array([0.0, 0.0])
    g = 2.0 # max accel
    if key_up:
        f[1] = -g
    if key_dn:
        f[1] = g
    if key_le:
        f[0] = -g
    if key_ri:
        f[0] = g
    a = f_to_a(f, 1, u_to_four(origin_u, c), c)
    origin_u += a * dt
    origin_r += origin_u * dt
    print(f"{np.linalg.norm(origin_u) / c:.0%} c")
    program['time'] = t_glob
    program['r0_ship'] = r0_ship(t_glob)
    program['origin_r'] = origin_r
    program['origin_u'] = origin_u
    program['thursters'] = [key_up, key_ri, key_dn, key_le]
    program.draw(gl.GL_TRIANGLE_STRIP)

@window.event
def on_key_press(key, modifiers):
    global key_up, key_dn, key_le, key_ri
    global origin_u, doppler
    if key == app.window.key.SPACE:
        origin_u = np.array([0, 1e-5])
    elif chr(key) == 'W':
        key_up = True
    elif chr(key) == 'A':
        key_le = True
    elif chr(key) == 'S':
        key_dn = True
    elif chr(key) == 'D':
        key_ri = True
    elif chr(key) == 'E':
        doppler = 1.0 - doppler
        program['doppler'] = doppler
    else:
        print("unknown key:", key)

@window.event
def on_key_release(key, modifiers):
    global key_up, key_dn, key_le, key_ri
    if key == app.window.key.SPACE:
        pass
    elif chr(key) == 'W':
        key_up = False
    elif chr(key) == 'A':
        key_le = False
    elif chr(key) == 'S':
        key_dn = False
    elif chr(key) == 'D':
        key_ri = False
    else:
        print("unknown key:", key)

@window.event
def on_mouse_scroll(x, y, dx, dy):
    global view_w
    view_w *= 0.8 ** dy
    program['view_w'] = view_w

@window.event
def on_mouse_motion(x, y, dx, dy):
    global view_offset
    # print(x, y)
    view_offset[0] = (x / window.width * 2 - 1 * 0.9)
    view_offset[1] = (y / window.height * 2 - 1 * 0.9)
    # Uncomment to enable view offset controlled by mouse
    # program['view_offset'] = view_offset


program = gloo.Program("vert.glsl", "frag.glsl", count=4)
program['time'] = 0.0
program['c'] = c
program['position'] = [(-1,-1), (-1, 1), ( 1,-1), ( 1, 1)]
program['texcoord'] = [( 0, 1), ( 0, 0), ( 1, 1), ( 1, 0)]
program['r_ship'] = rrr.astype('f4').view(gloo.TextureFloat1D)
program['u_ship'] = uuu_ship.astype('f4').view(gloo.TextureFloat1D)
program['origin_r'] = origin_r
program['origin_u'] = origin_u
program['thursters'] = [0, 0, 0, 0]
program['time_span'] = time_span
program['earth_tex'] = np.array(Image.open('antarctica_512.png'))
program['self_tex'] = np.array(Image.open('self.png'))
program['doppler'] = doppler
program['view_w'] = view_w
program['view_offset'] = view_offset

app.run()
