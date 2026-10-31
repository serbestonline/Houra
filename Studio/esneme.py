# Houra stretch clips: one MPFB character on a studio floor, posed per move and rendered as a square loop.
# Run: Blender -b -P esneme.py -- <move> <out_dir> [frames, e.g. 1,25 | keys | all]
import bpy, bmesh, sys, os, math
from mathutils import Vector, Matrix, Quaternion
from bl_ext.blender_org.mpfb.services.humanservice import HumanService

move, out = sys.argv[sys.argv.index('--') + 1:][:2]
which = (sys.argv[sys.argv.index('--') + 3:] or ["all"])[0]
os.makedirs(out, exist_ok=True)
HERE = os.path.dirname(os.path.abspath(__file__))
bpy.ops.wm.read_factory_settings(use_empty=True)
scene = bpy.context.scene

# ---------- character (same MPFB recipe as the DGID cinematic)
info = HumanService._create_default_human_info_dict()
info["phenotype"].update({"gender": 1.0, "age": 0.48, "weight": 0.5, "muscle": 0.58})
info["phenotype"]["race"] = {"asian": 0.1, "caucasian": 0.8, "african": 0.1}
info.update({"rig": "default", "hair": "short04.mhclo", "clothes": ["male_casualsuit06.mhclo", "female_sportsuit01.mhclo"],
             "skin_mhmat": "young_caucasian_male.mhmat", "eyebrows": "eyebrow006.mhclo",
             "eyes": "high-poly.mhclo", "eyelashes": "eyelashes01.mhclo",
             "skin_material_type": "ENHANCED_SSS", "eyes_material_type": "MAKESKIN", "alternative_materials": {}})
basemesh = HumanService.deserialize_from_dict(info, HumanService.get_default_deserialization_settings())
arm = basemesh.parent

# sport outfit from two suits: the t-shirt (blue copy of its texture) and the black tights of the sport suit
def keep_faces(prefix, keep):
    """Delete the faces of a clothing piece whose mean UV fails keep(u, v)."""
    o = next(c for c in bpy.data.objects if c.type == "MESH" and prefix in c.name.lower())
    bm = bmesh.new(); bm.from_mesh(o.data); uv = bm.loops.layers.uv.active
    gone = [f for f in bm.faces if not keep(sum(l[uv].uv.x for l in f.loops) / len(f.loops), sum(l[uv].uv.y for l in f.loops) / len(f.loops))]
    bmesh.ops.delete(bm, geom=gone, context='FACES'); bm.to_mesh(o.data); bm.free()
keep_faces("male_casualsuit06", lambda u, v: v > 0.57)              # shirt only, jeans gone
keep_faces("female_sportsuit01", lambda u, v: v < 0.55 and u < 0.72)  # tights only, top and sleeves gone
for img in bpy.data.images:
    if img.filepath.endswith("male_casualsuit06_diffuse.png"):
        img.filepath = os.path.join(HERE, "textures", "male_casualsuit06_diffuse_esneme.png"); img.reload()
for pb in arm.pose.bones:
    pb.rotation_mode = 'QUATERNION'
arm.rotation_mode = 'QUATERNION'
MESHES = [basemesh] + [c for c in bpy.data.objects if c.parent in (arm, basemesh) and c.type == 'MESH']

# ---------- posing helpers. Armature space: front -y, head +z, left +x. World: z up, floor at z = 0.
def upd(): bpy.context.view_layer.update()

def aim(name, d):
    """Rotate a pose bone about its head so it points along d (armature space)."""
    pb = arm.pose.bones[name]
    m = pb.matrix.copy(); head = m.translation.copy()
    q = (pb.tail - pb.head).normalized().rotation_difference(Vector(d).normalized())
    pb.matrix = Matrix.Translation(head) @ q.to_matrix().to_4x4() @ Matrix.Translation(-head) @ m
    upd()

def turn(name, axis, deg, move_by=None):
    """Rotate a pose bone about its head around an armature-space axis (and optionally shift it)."""
    pb = arm.pose.bones[name]; m = pb.matrix.copy(); head = m.translation.copy()
    r = Matrix.Rotation(math.radians(deg), 4, Vector(axis))
    pb.matrix = Matrix.Translation(head + Vector(move_by or (0, 0, 0))) @ r @ Matrix.Translation(-head) @ m
    upd()

def to_arm(d): return arm.matrix_world.to_3x3().normalized().inverted() @ Vector(d)
def aimw(name, d): aim(name, to_arm(d))
def P(name, tail=False):
    pb = arm.pose.bones[name]; return arm.matrix_world @ (pb.tail if tail else pb.head)
def norm(*v): return Vector(v).normalized()
def blen(names): return sum(arm.data.bones[n].length for n in names)

def body(h, f):
    """Orient the whole character: head toward h, chest toward f (world)."""
    h, f = Vector(h).normalized(), Vector(f).normalized()
    arm.rotation_quaternion = Matrix((h.cross(f), -f, h)).transposed().to_quaternion()
    upd()

def X(s): return 1 if s == "L" else -1
SPINE = ["spine05", "spine04", "spine03", "spine02", "spine01"]   # pelvis to chest
NECK = ["neck01", "neck02", "neck03", "head"]
LIMB = {"leg": (("upperleg01", "upperleg02"), ("lowerleg01", "lowerleg02")),
        "arm": (("upperarm01", "upperarm02"), ("lowerarm01", "lowerarm02", "wrist"))}

def spine(*dirs):
    """Spine directions from pelvis to chest (1, 2 or 5 values), then the neck, in armature space."""
    dirs = list(dirs); dirs += [dirs[-1]] * (5 - len(dirs))
    for n, d in zip(SPINE, dirs): aim(n, d)
def neck(d):
    for n in NECK: aim(n, d)

def leg(s, hip, knee, abd=0.06, twist=0.0):
    """Sagittal leg angles in degrees: hip flexion (0 = straight down the body), knee flexion; twist swings the leg sideways."""
    r = Matrix.Rotation(math.radians(twist), 3, 'Z')
    th, sh = math.radians(hip), math.radians(hip - knee)
    up, lo = LIMB["leg"]
    for n in up: aim(f"{n}.{s}", r @ norm(X(s) * abd, -math.sin(th), -math.cos(th)))
    for n in lo: aim(f"{n}.{s}", r @ norm(X(s) * abd * 0.5, -math.sin(sh), -math.cos(sh)))

def limb(s, kind, d, d2=None, world=False):
    """Point a whole arm or leg (upper part along d, lower along d2)."""
    up, lo = LIMB[kind]; f = aimw if world else aim
    for n in up: f(f"{n}.{s}", (X(s) * d[0], d[1], d[2]) if not world else d)
    d2 = d2 or d
    for n in lo: f(f"{n}.{s}", (X(s) * d2[0], d2[1], d2[2]) if not world else d2)

def reach(s, kind, target, pole):
    """Two-bone solve in world space: end of the limb (ankle or wrist) at target, middle joint toward pole."""
    up, lo = LIMB[kind]; lo = lo[:2]
    S, T = P(f"{up[0]}.{s}"), Vector(target)
    a, b = blen([f"{n}.{s}" for n in up]), blen([f"{n}.{s}" for n in lo])
    d = min((T - S).length, (a + b) * 0.995); u = (T - S).normalized()
    x = (a * a - b * b + d * d) / (2 * d); hgt = math.sqrt(max(a * a - x * x, 0.0))
    p = Vector(pole); w = (p - p.dot(u) * u).normalized()
    E = S + u * x + w * hgt; T = S + u * d
    for n in up: aimw(f"{n}.{s}", E - S)
    for n in lo: aimw(f"{n}.{s}", T - E)
    if kind == "arm": aimw(f"wrist.{s}", T - E)

def points(stride=3):
    dg = bpy.context.evaluated_depsgraph_get(); pts = []
    for o in MESHES:
        ev = o.evaluated_get(dg); me = ev.to_mesh(); mw = ev.matrix_world.copy()
        vs = me.vertices
        pts += [mw @ vs[i].co for i in range(0, len(vs), stride)]
        ev.to_mesh_clear()
    return pts

def ground():
    """Move the character so its lowest point touches the floor."""
    arm.location.z -= min(p.z for p in points()); upd()

def reset():
    arm.location = (0, 0, 0)
    for pb in arm.pose.bones:
        pb.rotation_quaternion = (1, 0, 0, 0); pb.location = (0, 0, 0)
    upd()

SUP = ((0, 1, 0), (0, 0, 1))     # on the back: head +y, chest up, left side toward +x
PRONE = ((0, 1, 0), (0, 0, -1))  # face down: head +y, left side toward -x
cache = {}

def floor_target(key, fn):
    """A planted hand or foot: its world position is fixed the first time and reused by every key."""
    if key not in cache: cache[key] = fn()
    return cache[key]

# ---------- moves
def dead_bug(reach_side=None):
    body(*SUP); ground_lock()
    for s in "LR":
        leg(s, 90, 90); aim(f"foot.{s}", (0, -1, -0.15))
        limb(s, "arm", (0.12, -1, 0))
    if reach_side:
        o = "R" if reach_side == "L" else "L"
        leg(o, 12, 0, abd=0.05); aim(f"foot.{o}", (0, -1, -0.6))
        limb(reach_side, "arm", (0.16, -0.25, 1))

TORSO = ("spine", "pelvis", "root", "breast", "clavicle", "shoulder")
def torso_min():
    """Lowest point of the trunk skin (masks off so vertex indices match the base mesh)."""
    masks = [m for m in basemesh.modifiers if m.type == 'MASK']
    for m in masks: m.show_viewport = False
    names = {g.index: g.name for g in basemesh.vertex_groups}
    bones = set(arm.data.bones.keys())
    def owner(v):
        gs = [g for g in v.groups if names.get(g.group) in bones]
        return names[max(gs, key=lambda g: g.weight).group] if gs else ""
    trunk = [v.index for v in basemesh.data.vertices if owner(v).startswith(TORSO)]
    dg = bpy.context.evaluated_depsgraph_get(); ev = basemesh.evaluated_get(dg); me = ev.to_mesh(); mw = ev.matrix_world.copy()
    z = min((mw @ me.vertices[i].co).z for i in trunk)
    ev.to_mesh_clear()
    for m in masks: m.show_viewport = True
    upd(); return z

def ground_lock():
    """Lying moves keep the trunk on the floor: place it once from the rest pose, then reuse that height."""
    if "z" not in cache:
        arm.location.z -= torso_min(); upd(); cache["z"] = arm.location.z
    arm.location.z = cache["z"]; upd()

def arms_down(s, out=0.14, back=0.08):
    limb(s, "arm", (out, back, -1))

def knee_hug(hip, knee):
    body(*SUP); ground_lock()
    neck((0, -0.12, 1))
    for s in "LR":
        leg(s, hip, knee, abd=0.1); aim(f"foot.{s}", (0, -0.3, -1))
    for s in "LR":
        k, a = P(f"lowerleg01.{s}"), P(f"lowerleg02.{s}", tail=True)
        reach(s, "arm", k + (a - k) * 0.28 + Vector((X(s) * 0.08, 0, 0.09)), (X(s), 0, 0.6))

def twist(angle):
    body(*SUP); ground_lock()
    turn("root", (0, 0, 1), angle * 0.5)
    turn("spine05", (0, 0, 1), -angle * 0.5)
    for s in "LR":
        leg(s, 90, 95, abd=0.03, twist=angle); aim(f"foot.{s}", Matrix.Rotation(math.radians(angle), 3, 'Z') @ Vector((0, -1, -0.2)))
        limb(s, "arm", (1, 0.05, 0.12))
    neck((0, 0, 1)); turn("neck01", (0, 0, 1), -angle * 0.25)

def bent_knees(sides="LR"):
    for s in sides:
        H = P(f"upperleg01.{s}")
        T = floor_target(f"foot{s}", lambda: Vector((H.x + X(s) * 0.03, H.y - 0.43, 0.085)))
        reach(s, "leg", T, (0, 0, 1)); aimw(f"foot.{s}", (0, -1, -0.45))

def bridge(up):
    body(*SUP); ground_lock()
    if up:
        turn("root", (1, 0, 0), 0, move_by=(0, -0.2, 0))
        spine((0, 0.36, 0.93), (0, 0.36, 0.93), (0, 0.33, 0.94), (0, 0.25, 0.97), (0, 0.1, 1)); neck((0, 0, 1))
    for s in "LR": arms_down(s, 0.12, 0.05)
    bent_knees()

def curl_up(up):
    body(*SUP); ground_lock()
    if up:
        spine((0, 0, 1), (0, 0, 1), (0, -0.12, 1), (0, -0.3, 0.95), (0, -0.4, 0.92)); neck((0, -0.42, 0.9))
    bent_knees("L")
    leg("R", 0, 0, abd=0.04); aim("foot.R", (0, -1, -0.3))
    for s in "LR":
        lb = P("spine04"); reach(s, "arm", Vector((lb.x + X(s) * 0.24, lb.y + 0.04, 0.06)), (X(s), 0, 0.3))
        aimw(f"wrist.{s}", (0, -1, 0.1))

def side_plank(up):
    # lying on the left side, chest toward the camera (+x)
    if up:
        tilt = math.radians(11); body((0, math.cos(tilt), math.sin(tilt)), (1, 0, 0))
        spine((0, 0, 1)); neck((0, 0, 1))
        for s in "LR": leg(s, 0, 0, abd=0.0)
    else:
        body((0, 1, 0), (1, 0, 0))
        spine((-0.3, 0, 0.95), (-0.5, 0, 0.87), (-0.55, 0, 0.84)); neck((-0.3, 0, 0.95))
        for s in "LR": leg(s, 0, 0, abd=0.0)
    for s in "LR": aim(f"foot.{s}", (0, -1, -0.3))
    limb("L", "arm", (0, 0, -1), world=True)
    for n in ("lowerarm01.L", "lowerarm02.L", "wrist.L"): aimw(n, (1, 0.15, 0))
    limb("R", "arm", (0.05, 0, 1), world=True)
    ground()

def quad(pull):
    # lying on the right side, chest toward -x (camera on that side), top leg is the left one
    body((0, 1, 0), (-1, 0, 0))
    spine((0, 0, 1)); neck((0, 0, 1))
    leg("R", 25, 35, abd=0.0); aim("foot.R", (0, -1, -0.3))
    limb("R", "arm", (0.0, -0.1, 1), world=False)
    if pull == 0.5:
        leg("L", 0, 110, abd=0.03); aim("foot.L", (0, 1, 0.2))
        reach("L", "arm", P("foot.L") + Vector((0.2, 0.05, 0.12)), (1, 0.2, 0.6))
    elif pull:
        leg("L", -18 - 8 * (pull - 1), 150, abd=0.02); aim("foot.L", (0, 1, 0.4))
        reach("L", "arm", P("foot.L") + Vector((0.13, 0.03, 0.11)), (1, 0.2, 0.6))
    else:
        leg("L", 18, 22, abd=0.0); aim("foot.L", (0, -1, -0.3))
        limb("L", "arm", (0.12, -0.1, -1))
    ground()

def prone(lift):
    body(*PRONE); ground_lock()
    for s in "LR":
        leg(s, 0, 0, abd=0.04); aim(f"foot.{s}", (0, -0.25, -1))
    if lift:
        spine((0, 0, 1), (0, 0.06, 1), (0, 0.16, 0.99), (0, 0.3, 0.95), (0, 0.38, 0.93)); neck((0, 0.32, 0.95))
        for s in "LR": limb(s, "arm", (0.12, 0.28, -1))
    else:
        for s in "LR": limb(s, "arm", (0.12, 0.02, -1))

def up_dog(up):
    body(*PRONE); ground_lock()
    for s in "LR":
        leg(s, 0, 0, abd=0.05); aim(f"foot.{s}", (0, -0.25, -1))
    if up:
        spine((0, 0.3, 0.95), (0, 0.5, 0.87), (0, 0.65, 0.76), (0, 0.72, 0.69), (0, 0.72, 0.69)); neck((0, 0.45, 0.89))
    for s in "LR":
        Sh = P(f"upperarm01.{s}")
        T = floor_target(f"hand{s}", lambda: Vector((Sh.x - X(s) * 0.06, Sh.y - 0.16, 0.065)))
        reach(s, "arm", T, (0, -0.6, 1)); aimw(f"wrist.{s}", (0, 1, 0.05))

def chair_glute(lean):
    body((0, 0, 1), (0, -1, 0))
    l = 0.18 + 0.18 * lean
    spine((0, -l * 0.6, 1), (0, -l, 1), (0, -l, 1), (0, -l * 1.1, 1), (0, -l * 1.1, 1)); neck((0, -l * 0.8, 1))
    leg("R", 90, 90, abd=0.1)
    k = P("lowerleg01.R")
    reach("L", "leg", k + Vector((0.02, 0.05, 0.14)), (1, -0.3, 0.4)); aimw("foot.L", (-1, -0.15, 0.1))
    reach("L", "arm", P("lowerleg01.L") + Vector((0, 0, 0.1)), (1, 0.3, -0.2))
    reach("R", "arm", P("foot.L") + Vector((0, -0.05, 0.12)), (-0.6, -1, -0.3))
    ground()

def pelvic_stand(tilt):
    body((0, 0, 1), (0, -1, 0))
    turn("root", (1, 0, 0), tilt)
    spine((0, 0, 1)); neck((0, 0, 1))
    for s in "LR":
        leg(s, 12, 22, abd=0.05); aim(f"foot.{s}", (0, -1, -0.35))
        hand_on_hip(s)
    ground()

def stand(arms=True):
    """Upright, facing -y: straight spine and legs, arms hanging."""
    body((0, 0, 1), (0, -1, 0))
    spine((0, 0, 1)); neck((0, 0, 1))
    for s in "LR":
        leg(s, 0, 0, abd=0.05)
        if arms: limb(s, "arm", (0.2, 0.02, -1))

def stand_lock():
    """Standing moves keep the feet where the first key put them."""
    if "standz" not in cache:
        ground(); cache["standz"] = arm.location.z
    arm.location.z = cache["standz"]; upd()

def hand_on_hip(s):
    reach(s, "arm", P(f"upperleg01.{s}") + Vector((X(s) * 0.15, 0.02, 0.16)), (X(s), 0.8, 0))

def other(s): return "R" if s == "L" else "L"

def neck_tilt(side):
    """Head tilts toward side; that side's hand rests over the head and eases it down."""
    stand()
    if side:
        x = X(side)
        for n, k in zip(NECK, (0.25, 0.35, 0.45, 0.5)): aim(n, (x * k, 0, 1))
        reach(side, "arm", P("head", tail=True) + Vector((-x * 0.13, 0.01, -0.06)), (x * 0.2, 0.05, 1)); aimw(f"wrist.{side}", (-x * 0.25, 0, -1))
    stand_lock()

def neck_forward(side):
    """Hands clasped behind the head, head eased forward and toward side's armpit."""
    stand()
    if side: neck((X(side) * 0.22, -0.48, 0.85))
    hd = P("head"); back = arm.matrix_world.to_3x3() @ Vector((0, 1, 0))
    for s in "LR":
        reach(s, "arm", hd + back * 0.1 + Vector((X(s) * 0.09, 0, 0.07)), (X(s), -0.4, 0.3)); aimw(f"wrist.{s}", (-X(s) * 0.3, 0.2, 1))
    stand_lock()

def side_bend(side, phase="hold"):
    """Bend toward side with the other arm over the head, side's hand on the hip."""
    stand()
    if side:
        x = X(side); o = other(side)
        if phase == "pre":
            limb(o, "arm", (1, 0.05, 0.1)); stand_lock(); return
        spine((x * 0.05, 0, 1), (x * 0.12, 0, 1), (x * 0.2, 0, 1), (x * 0.3, 0, 0.95), (x * 0.36, 0, 0.93)); neck((x * 0.32, 0, 0.95))
        for n in LIMB["arm"][0]: aim(f"{n}.{o}", (x * 0.35, 0.05, 0.94))
        for n in LIMB["arm"][1]: aim(f"{n}.{o}", (x * 0.85, 0.0, 0.5))
        limb(side, "arm", (X(side) * 0.3, 0.02, -1), world=True)
    stand_lock()

def arms_pre(side, up=False):
    """Both arms forward in front of the body: the stretching arm straight, the other one bent."""
    o = other(side)
    limb(side, "arm", (0.12, -0.6, 0.8) if up else (0.12, -1, -0.15))
    limb(o, "arm", (0.12, -0.45, -0.9), (-0.3, -1, 0.3))

def grip_hand(s, deg=35):
    """Curl the four fingers (not the thumb) of a hand so it holds instead of waving."""
    for pb in arm.pose.bones:
        if pb.name.startswith("finger") and not pb.name.startswith("finger1") and pb.name.endswith("." + s):
            pb.rotation_quaternion = Quaternion((1, 0, 0), math.radians(deg))
    upd()

def triceps(side, phase="hold"):
    """Arm straight up, then the elbow folds so the hand drops behind the head to the upper back; the other hand holds the elbow from behind the head."""
    stand()
    if side:
        x = X(side); o = other(side)
        up = (-x * 0.25, 0.45, 1)   # upper arm upright against the head, elbow up and a little behind it
        if phase == "pre":
            limb(side, "arm", (0.1, 0.05, 1)); limb(o, "arm", (0.6, 0.05, -0.8))
        else:
            neck((0, -0.4, 1))
            for n in LIMB["arm"][0]: aim(f"{n}.{side}", up)
            mid = phase == "mid"   # mid: elbow half bent, forearm points back
            for n in LIMB["arm"][1]: aim(f"{n}.{side}", (-x * 0.2, 1, 0.15) if mid else (-x * 0.3, 0.32, -0.9))
            M = arm.matrix_world.to_3x3().normalized()
            U, Sd, B = M @ Vector((0, 0, 1)), M @ Vector((x, 0, 0)), M @ Vector((0, 1, 0))
            # the other arm is too short to go over the top of the head, so it holds the elbow from behind the head
            if mid: limb(o, "arm", (0.7, 0.3, 0.6))
            else: reach(o, "arm", P(f"lowerarm01.{side}") + B * 0.04 + U * 0.04, -Sd * 0.6 + U * 0.5 + B * 0.5); grip_hand(o)
    stand_lock()

def across(side, phase, d, grip, pole):
    """Side's arm straight across the chest along d; the other hand holds it at grip (a point on that arm)."""
    stand()
    if side:
        x = X(side); o = other(side)
        if phase == "pre": arms_pre(side)
        else:
            for n in LIMB["arm"][0] + LIMB["arm"][1]: aim(f"{n}.{side}", (x * d[0], d[1], d[2]))
            if phase == "mid": limb(o, "arm", (0.15, -0.35, -0.95), (0.0, -1, -0.35))
            else: reach(o, "arm", grip(side), (-x * pole[0], pole[1], pole[2])); aimw(f"wrist.{o}", (x * 0.3, -0.2, 1))
    stand_lock()

def cross_body(side, phase="hold"):
    """The other forearm comes up in front and holds the arm just above the elbow."""
    def grip(s):
        e, sh = P(f"lowerarm01.{s}"), P(f"upperarm01.{s}")
        return e + (sh - e) * 0.4 + Vector((0, -0.1, -0.03))
    across(side, phase, (-0.6, -0.8, -0.1), grip, (-0.1, -1, -1))
def upper_arm(side, phase="hold"):
    across(side, phase, (-0.6, -0.8, 0.05), lambda s: P(f"lowerarm01.{s}") + (P(f"upperarm01.{s}") - P(f"lowerarm01.{s}")) * 0.3 + Vector((0, -0.08, -0.03)), (-0.1, -1, -1))
def wrist_pull(side, phase="hold"):
    across(side, phase, (-0.4, -0.6, -0.7), lambda s: P(f"lowerarm02.{s}") + (P(f"wrist.{s}") - P(f"lowerarm02.{s}")) * 0.2 + Vector((0, -0.09, 0)), (-0.2, -1, -0.6))

def chest_open(opened):
    stand()
    for s in "LR":
        limb(s, "arm", (1, 0.35, 0.05) if opened else (0.1, -1, 0.05))
    stand_lock()

def upper_back(rounded):
    stand()
    if rounded:
        spine((0, 0, 1), (0, -0.05, 1), (0, -0.15, 0.99), (0, -0.28, 0.96), (0, -0.4, 0.92)); neck((0, -0.45, 0.89))
    ch = P("spine01")
    T = ch + Vector((0, -0.55 - 0.1 * rounded, -0.06 - 0.06 * rounded))
    for s in "LR": reach(s, "arm", T + Vector((X(s) * 0.08, 0, 0)), (X(s), 0, -0.5)); aimw(f"wrist.{s}", (-X(s) * 0.15, -1, 0))
    stand_lock()

def wrist_circle(t):
    stand()
    for s in "LR":
        for n in LIMB["arm"][0]: aim(f"{n}.{s}", (X(s) * 0.12, -0.25, -1))
        for n in LIMB["arm"][1][:2]: aim(f"{n}.{s}", (X(s) * 0.05, -1, 0.05))
        a = math.radians(t)
        aim(f"wrist.{s}", (X(s) * 0.6 * math.cos(a), -1, 0.6 * math.sin(a)))
    stand_lock()

def squat_reach(depth):
    """depth 0 = standing with arms overhead, 1 = full squat with arms forward."""
    stand(arms=False)
    if not depth:
        for s_ in "LR": limb(s_, "arm", (0.15, 0.05, 1))
        stand_lock()
        for s_ in "LR":
            floor_target(f"foot{s_}", lambda: P(f"foot.{s_}"))
            floor_target(f"footdir{s_}", lambda: P(f"foot.{s_}", tail=True) - P(f"foot.{s_}"))
        return
    stand_lock()
    turn("root", (1, 0, 0), 0, move_by=(0, 0.14 * depth, -0.4 * depth))
    spine((0, -0.3 * depth, 0.95), (0, -0.4 * depth, 0.92), (0, -0.42 * depth, 0.9)); neck((0, -0.15 * depth, 1))
    for s_ in "LR":
        reach(s_, "leg", cache[f"foot{s_}"], (X(s_) * 0.35, -1, 0.2))
        aimw(f"foot.{s_}", cache[f"footdir{s_}"])
        a = math.radians(90 * depth)
        limb(s_, "arm", (0.15 - 0.05 * depth, -math.sin(a), math.cos(a) + 0.15 * depth))

def scap_push(shift):
    """Hands on a desk, body in a straight incline; the chest sinks toward the desk or pushes away (along the chest axis)."""
    a = math.radians(35)
    h, f = Vector((0, -math.sin(a), math.cos(a))), Vector((0, -math.cos(a), -math.sin(a)))
    body(h, f)
    spine((0, 0, 1)); neck((0, -0.05, 1))
    for s in "LR": leg(s, 0, 0, abd=0.06); aimw(f"foot.{s}", (0, -0.5, -1))
    if "deskz" not in cache:
        for s in "LR": limb(s, "arm", (0.06, -1, 0))
        ground(); cache["deskz"] = arm.location.z
        for s in "LR": cache[f"hand{s}"] = P(f"wrist.{s}") + Vector((0, 0, 0.02))
        cache["toez"] = min(P(f"foot.{s}", tail=True).z for s in "LR")
    arm.location = f * shift + Vector((0, 0, cache["deskz"])); upd()
    arm.location.z -= min(P(f"foot.{s}", tail=True).z for s in "LR") - cache["toez"]; upd()
    for s in "LR": reach(s, "arm", cache[f"hand{s}"], (X(s), 0.3, -0.2)); aimw(f"wrist.{s}", (0, -1, -0.1))

L = lambda f, *a: (lambda: f(*a))
SIDES = lambda f, a="R", b="L": [(1, L(f, None)), (21, L(f, a)), (41, L(f, a)), (49, L(f, None)), (69, L(f, b)), (89, L(f, b)), (97, L(f, None))]
SIDESP = lambda f, a="L", b="R": [(1, L(f, None)), (10, L(f, a, "pre")), (22, L(f, a)), (40, L(f, a)), (46, L(f, a, "pre")), (52, L(f, None)),
                                  (58, L(f, b, "pre")), (70, L(f, b)), (88, L(f, b)), (94, L(f, b, "pre")), (97, L(f, None))]
SIDESM = lambda f, a="L", b="R": [(1, L(f, None)), (7, L(f, a, "pre")), (14, L(f, a, "mid")), (22, L(f, a)), (38, L(f, a)), (43, L(f, a, "mid")), (48, L(f, a, "pre")), (52, L(f, None)),
                                  (57, L(f, b, "pre")), (63, L(f, b, "mid")), (70, L(f, b)), (84, L(f, b)), (88, L(f, b, "mid")), (92, L(f, b, "pre")), (97, L(f, None))]
UPPER = {"neck", "neckforward", "triceps", "crossbody", "upperarm", "wristpull", "chest", "upperback", "wrists"}
MOVES = {   # move: (keys, camera azimuth, camera elevation)
    "neck":        (SIDES(neck_tilt), -75, 6),          # first toward the right: the left side stretches
    "neckforward": (SIDES(neck_forward), -60, 10),
    "sidebend":    (SIDESP(side_bend, "R", "L"), -85, 6),
    "triceps":     (SIDESM(triceps), 50, 10),     # from behind: the hand between the shoulder blades
    "crossbody":   (SIDESM(cross_body), -65, 8),
    "upperarm":    (SIDESM(upper_arm), -65, 8),
    "wristpull":   (SIDESM(wrist_pull), -65, 8),
    "chest":       ([(1, L(chest_open, False)), (25, L(chest_open, True)), (49, L(chest_open, False)), (73, L(chest_open, True)), (97, L(chest_open, False))], -45, 12),
    "upperback":   ([(1, L(upper_back, 0)), (25, L(upper_back, 1)), (61, L(upper_back, 1.15)), (97, L(upper_back, 0))], -25, 8),
    "wrists":      ([(1 + 12 * i, L(wrist_circle, 90 * i)) for i in range(9)], -55, 14),
    "squatreach":  ([(1 + 6 * i, L(squat_reach, [0, 0.25, 0.5, 0.75, 1, 0.75, 0.5, 0.25][i % 8])) for i in range(17)], -35, 10),
    "scappush":    ([(1, L(scap_push, 0)), (25, L(scap_push, 0.05)), (49, L(scap_push, -0.04)), (73, L(scap_push, 0.05)), (97, L(scap_push, 0))], -18, 14),
    "deadbug": ([(1, L(dead_bug)), (25, L(dead_bug, "L")), (49, L(dead_bug)), (73, L(dead_bug, "R")), (97, L(dead_bug))], -14, 25),
    "kneehug": ([(1, L(knee_hug, 105, 120)), (25, L(knee_hug, 130, 148)), (61, L(knee_hug, 138, 152)), (97, L(knee_hug, 105, 120))], -14, 25),
    "twist":   ([(1, L(twist, 0)), (25, L(twist, 62)), (49, L(twist, 0)), (73, L(twist, -62)), (97, L(twist, 0))], -35, 38),
    "bridge":  ([(1, L(bridge, False)), (25, L(bridge, True)), (49, L(bridge, False)), (73, L(bridge, True)), (97, L(bridge, False))], -14, 18),
    "curlup":  ([(1, L(curl_up, False)), (21, L(curl_up, True)), (77, L(curl_up, True)), (97, L(curl_up, False))], -14, 18),
    "sideplank": ([(1, L(side_plank, False)), (25, L(side_plank, True)), (73, L(side_plank, True)), (97, L(side_plank, False))], -12, 14),
    "quad":    ([(1, L(quad, 0)), (13, L(quad, 0.5)), (25, L(quad, 1)), (61, L(quad, 2)), (79, L(quad, 0.5)), (97, L(quad, 0))], 160, 32),
    "prone":   ([(1, L(prone, False)), (25, L(prone, True)), (49, L(prone, False)), (73, L(prone, True)), (97, L(prone, False))], 14, 20),
    "updog":   ([(1, L(up_dog, False)), (25, L(up_dog, True)), (49, L(up_dog, False)), (73, L(up_dog, True)), (97, L(up_dog, False))], 14, 16),
    "chairglute": ([(1, L(chair_glute, 0)), (25, L(chair_glute, 1)), (61, L(chair_glute, 1.2)), (97, L(chair_glute, 0))], -28, 12),
    "pelvicstand": ([(1, L(pelvic_stand, 0)), (25, L(pelvic_stand, 18)), (49, L(pelvic_stand, 0)), (73, L(pelvic_stand, -16)), (97, L(pelvic_stand, 0))], -5, 8),
}
keys, AZ, EL = MOVES[move]

for frame, pose in keys:
    reset(); pose()
    arm.keyframe_insert("location", frame=frame); arm.keyframe_insert("rotation_quaternion", frame=frame)
    for pb in arm.pose.bones:
        pb.keyframe_insert("rotation_quaternion", frame=frame)
    arm.pose.bones["root"].keyframe_insert("location", frame=frame)
scene.frame_start, scene.frame_end = 1, keys[-1][0] - 1
scene.render.fps = 24

def check():
    """Print body parts that pass through each other (non-neighbouring skin triangles that intersect) and dips below the floor."""
    from mathutils.bvhtree import BVHTree
    from collections import Counter
    for m in basemesh.modifiers:
        if m.type == 'MASK': m.show_viewport = False
    names = {g.index: g.name for g in basemesh.vertex_groups}; bones = set(arm.data.bones.keys())
    helper = {g.index for g in basemesh.vertex_groups if g.name in ("HelperGeometry", "JointCubes")}
    def cat(bn):
        side = bn[-2:] if bn[-2:] in (".L", ".R") else ""
        b = bn.split(".")[0]
        for pre, c in ((("spine", "pelvis", "root", "breast", "clavicle", "shoulder"), "torso"), (("upperarm",), "uarm"), (("lowerarm",), "farm"),
                       (("wrist", "finger", "thumb", "metacarpal", "index", "middle", "ring", "pinky", "hand"), "hand"),
                       (("upperleg",), "thigh"), (("lowerleg",), "shin"), (("foot", "toe"), "foot")):
            if b.startswith(pre): return c if c == "torso" else c + side
        return "head"
    vcat, vhelp = [], []
    for v in basemesh.data.vertices:
        gs = [g for g in v.groups if names.get(g.group) in bones]
        vcat.append(cat(names[max(gs, key=lambda g: g.weight).group]) if gs else "head")
        vhelp.append(any(g.group in helper and g.weight > 0 for g in v.groups))
    polys, pcat = [], []
    for p in basemesh.data.polygons:
        if any(vhelp[i] for i in p.vertices): continue
        polys.append(list(p.vertices)); pcat.append(Counter(vcat[i] for i in p.vertices).most_common(1)[0][0])
    ok = {frozenset(("torso", "head")), frozenset(("thigh.L", "thigh.R"))}
    for s in (".L", ".R"):
        for a, b in (("torso", "uarm"), ("uarm", "farm"), ("farm", "hand"), ("torso", "thigh"), ("thigh", "shin"), ("shin", "foot")):
            ok.add(frozenset((a if a == "torso" else a + s, b + s)))
    worst, at = Counter(), {}
    for f in range(scene.frame_start, scene.frame_end + 1, 2):
        scene.frame_set(f)
        dg = bpy.context.evaluated_depsgraph_get(); ev = basemesh.evaluated_get(dg); me = ev.to_mesh(); mw = ev.matrix_world.copy()
        assert len(me.vertices) == len(vcat), "modifier changed the vertex count"
        verts = [mw @ v.co for v in me.vertices]; ev.to_mesh_clear()
        t = BVHTree.FromPolygons(verts, polys)
        c = Counter()
        for i, j in t.overlap(t):
            if pcat[i] != pcat[j] and frozenset((pcat[i], pcat[j])) not in ok:
                c["-".join(sorted((pcat[i], pcat[j])))] += 1
        if os.environ.get("CHECKV") and c: print("F", f, dict(c))
        for k, v in enumerate(verts):
            if not vhelp[k] and v.z < -0.01:
                c[f"floor_{vcat[k]}"] = max(c[f"floor_{vcat[k]}"], int(-v.z * 1000))
        for k, n in c.items():
            if n > worst[k]: worst[k], at[k] = n, f
    print("CHECK", move, " ".join(f"{k}={n}@{at[k]}" for k, n in worst.most_common()) or "clean")

if which == "check":
    check(); sys.exit(0)

# ---------- studio: soft grey floor, light world, three area lights
floor_mat = bpy.data.materials.new("floor"); floor_mat.use_nodes = True
bsdf = floor_mat.node_tree.nodes["Principled BSDF"]
bsdf.inputs["Base Color"].default_value = (0.62, 0.62, 0.63, 1); bsdf.inputs["Roughness"].default_value = 0.9
bpy.ops.mesh.primitive_plane_add(size=30, location=(0, 0, 0)); bpy.context.object.data.materials.append(floor_mat)
scene.world = bpy.data.worlds.new("w"); scene.world.use_nodes = True
scene.world.node_tree.nodes["Background"].inputs[0].default_value = (0.86, 0.86, 0.87, 1)
scene.world.node_tree.nodes["Background"].inputs[1].default_value = 0.35

if move == "chairglute":   # a plain black stool under the seat
    scene.frame_set(1)
    root = P("root"); pts = [p for p in points(2) if (p.xy - root.xy).length < 0.2 and p.z < root.z]
    seat = min(p.z for p in pts); cx, cy = root.x, root.y - 0.03
    stool = bpy.data.materials.new("stool"); stool.use_nodes = True
    stool.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
    stool.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.5
    bpy.ops.mesh.primitive_cylinder_add(radius=0.2, depth=0.04, location=(cx, cy, seat - 0.02)); bpy.context.object.data.materials.append(stool)
    for i in range(4):
        a = math.pi / 4 + i * math.pi / 2
        bpy.ops.mesh.primitive_cylinder_add(radius=0.018, depth=seat - 0.04, location=(cx + 0.14 * math.cos(a), cy + 0.14 * math.sin(a), (seat - 0.04) / 2))
        bpy.context.object.data.materials.append(stool)

if move == "scappush":   # a plain desk under the planted hands
    top = min(cache["handL"].z, cache["handR"].z) - 0.035; hy = (cache["handL"].y + cache["handR"].y) / 2
    desk = bpy.data.materials.new("desk"); desk.use_nodes = True
    desk.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.03, 0.03, 0.035, 1)
    desk.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.45
    bpy.ops.mesh.primitive_cube_add(location=(0, hy - 0.25, top - 0.02)); d = bpy.context.object
    d.scale = (0.6, 0.32, 0.02); d.data.materials.append(desk)
    for lx in (-0.55, 0.55):
        for ly in (hy + 0.03, hy - 0.53):
            bpy.ops.mesh.primitive_cube_add(location=(lx, ly, (top - 0.04) / 2)); o = bpy.context.object
            o.scale = (0.02, 0.02, (top - 0.04) / 2); o.data.materials.append(desk)

# ---------- camera: fixed direction per move, distance fitted to every key pose
cam = bpy.data.objects.new("cam", bpy.data.cameras.new("cam")); scene.collection.objects.link(cam); scene.camera = cam
cam.data.lens = 60; tan_half = 18 / 60
az, el = math.radians(AZ), math.radians(EL)
back = Vector((math.cos(el) * math.cos(az), math.cos(el) * math.sin(az), math.sin(el)))
fwd = -back; right = fwd.cross(Vector((0, 0, 1))).normalized(); upv = right.cross(fwd)
pts = []
for frame, _ in keys[:-1]:
    scene.frame_set(frame); fp = points(6)
    if move in UPPER:   # arm and neck moves: frame from the hips up
        hz = P("root").z - 0.12; fp = [p for p in fp if p.z > hz]
    pts += fp
c = sum(pts, Vector()) / len(pts)
xs = [(p - c).dot(right) for p in pts]; ys = [(p - c).dot(upv) for p in pts]
c += right * (min(xs) + max(xs)) / 2 + upv * (min(ys) + max(ys)) / 2
dist = max(max(abs((p - c).dot(right)), abs((p - c).dot(upv))) / (tan_half * 0.86) - (p - c).dot(fwd) for p in pts)
cam.location = c + back * dist
cam.rotation_euler = fwd.to_track_quat('-Z', 'Y').to_euler()

target = c
for name, loc, power, size in [("key", (2.2, -1.0, 3.0), 320, 2.5), ("fill", (-2.5, 0.5, 2.2), 110, 3.0), ("rim", (0.5, 3.0, 2.0), 160, 2.0)]:
    l = bpy.data.objects.new(name, bpy.data.lights.new(name, 'AREA')); l.data.energy = power; l.data.size = size
    l.location = target + Vector(loc); l.rotation_euler = (target - l.location).to_track_quat('-Z', 'Y').to_euler()
    scene.collection.objects.link(l)

scene.render.engine = 'BLENDER_EEVEE'
for attr, val in (("taa_render_samples", 48), ("use_shadows", True), ("use_raytracing", True)):
    if hasattr(scene.eevee, attr): setattr(scene.eevee, attr, val)
scene.view_settings.view_transform = 'AgX'
scene.render.resolution_x = scene.render.resolution_y = 540
if which == "all": frames = range(scene.frame_start, scene.frame_end + 1, 2)
elif which == "keys": frames = [f for f, _ in keys[:-1]]
else: frames = [int(f) for f in which.split(",")]
for f in frames:
    scene.frame_set(f)
    scene.render.filepath = os.path.join(out, f"{move}_{f:03d}.png")
    bpy.ops.render.render(write_still=True)
    print("RENDERED", scene.render.filepath)
