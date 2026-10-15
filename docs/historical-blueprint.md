# Historical blueprint — reference only

This is the previous README, preserved verbatim below. Its proposals and performance claims are not current requirements or verified results. See [the current README](../README.md) and [working agreement](../COLLABORATION.md).

---

# Pest-Control-
RTS blueprint for an insect based RTS game
9:05
,1h
00000.....
pest-control-ultimate-technical...
109 sources • 13d ago
Pest Control: Ultimate Technical & Artistic Development Manual
This manual serves as the definitive engineering, pipeline, and game design blueprint for the development of Pest Control, a high-fidelity, highly competitive 1v1 multiplayer Real-Time Strategy (RTS) game. It compiles and synthesizes the exact mathematical formulations, visual workflows, networking models, and structural paradigms extracted from our extensive engineering documentation and research sources.
SECTION 1: Game Architecture & High-Performance Memory Layout
To simulate hundreds of autonomous, pathfinding insects on-screen simultaneously (up to 200+ agents per player) without dropping below 60 FPS, Pest Control adopts an Entity-Component-System (ECS) architecture. Traditional object-oriented hierarchies suffer from severe CPU cache thrashing due to scattered memory allocations (Pointer Chasing); ECS structures memory as contiguous cache-friendly arrays.
1.1 Sparse-Set vs. Archetype ECS
Implementations
Our technical blueprint evaluates two primary approaches for organising entity memory:
1. Archetype-Based ECS (e.g., Flecs): Entities with the exact same component composition are grouped together in columnar tables called Archetypes.
2. Sparse-Set ECS (e.g., EnTT): Each component type is atanadin ita auna alahal ananaa
.:..
9:05
,1h
dasc00ggg0000o
pest-control-ultimate-technical...
109 sources • 13d ago
is stored in its own global sparse-dense vector pair.
Entities are simple integer IDs pointing to indices within these arrays.
Empirical Performance Comparison (Conway's
Game of Life & Swarm Simulation)
Empirical benchmarks run on up to 50,000 active entities reveal clear architectural trade-offs:
• Multi-Component Iteration Performance: At 50,000 entities, Archetype ECS achieves nearly double the performance ($2 imes$ frame latency stability) compared to Sparse-Set. Because entities are packed contiguously in memory tables, the CPU can prefetch entire arrays of components into L1/L2 caches without lookup indirection.
• Structural Mutation Cost: Sparse-Set ECS is $6.6
imes$ faster at creating/destroying entities or adding/removing components (Median cost of 1,000ns vs. Archetype's 6,600ns). Adding a component in Archetype ECS forces the engine to migrate all existing components of that entity into a completely different table, incurring hefty memory copy and reallocation overheads.
• Component Sparsity: When components are rare or dynamic, Archetype tables fragment into thousands of small, under-utilized tables, causing memory overhead. Sparse-Set memory allocations scale linearly with component presence.
1.2 Multi-Core Parallelism & Staged Mutation
Deferral
To safely execute simulation updates in parallel across multi-core CPUs:
1. Read/Write Locking: Systems that only read
2. 9:05
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
1. Read/Write Locking: Systems that only read component data (e.g., RenderSystem, PathfindingSensorSystem) are grouped and executed concurrently. Systems that write to the same components (e.g., MovementSystem, DamageSystem) are serialized or execute on isolated, lock-protected archetype slices.
2. Staged Deferred Event Queues: Modifying the structure of an entity (adding/removing components or deleting the entity) during system iteration is not thread-safe and invalidates active array pointers. To solve this, all structural mutations are staged as lightweight event commands in a thread-safe Deferred Event Queue.
3. Synchronisation Step: Between frame updates, the game loop pauses system execution, enters a single-threaded execution phase, flushes the event queue, processes table migrations contiguously, and prepares the next frame state.
SECTION 2: 2D & 3D Character Art and Animation Pipelines
The visual identity of Pest Control relies on creating fluid, highly detailed, and directionally accurate insect animations. We support two primary production pipelines: Skeletal 2D (Spine 2D) and 3D-to-2D Sprite Rendering (Blender + Shader pipelines).
2.1 Spine 2D Skeletal Animation & 2.5D Mesh
Warping
To avoid the huge texture memory footprint of classic frame-by-frame animation, characters are rigged as skeletal meshes.
A A AA
-・］・・
2.1.1 Asymmetric Rigging (Multi-Skeleton Setup)
While symmetric characters can be animated in 5 directions and horizontally mirrored to cover 8 directions, this breaks when insects have asymmetrical designs (e.g., a soldier ant holding a heavy mandible weapon on its left, or a beetle with an asymmetrical scar pattern).
• The Solution: We deploy two distinct Spine skeletons:
• Front-Facing Skeleton: Configured for South
(S), Southeast (SE), Southwest (SW), East (E), and West (W).
• Back-Facing Skeleton: Configured for North
(N), Northeast (NE), and Northwest (NW).
• This keeps bone hierarchies clear and eliminates the visual glitch of "floating" weapon attachments flipping sides when the character turns.
2.1.2 2.5D Mesh Warping & Turning
To simulate 3D rotation within a flat 2D workspace:
1. Convert flat body segment textures (e.g., the pronotum or head capsule) into Free-Form Deformation (FFD) Meshes.
2. Bind these mesh vertices to dual, opposed control bones: face-control and back-control.
3. Set up Transform Constraints such that moving face-control horizontally to the right skews and warps the mesh vertices to contract on the right side while stretching on the left, simulating a cylindrical yaw rotation. The back-control bone is set with a negative translation offset, moving in the opposite direction to warp the rear armor segments accordingly
4. 2.1.3 Spine Attachment Swapping
When a character turns past a major $45^lcirc$ angle, simply rotating bones is insufficienta the asset itself
must change (e.g., swapping a front-facing mandible texture for a side-profile texture).
• The Transition Rule: Swap attachment textures during frames of maximum speed or physical deformation (such as the middle of a walk-cycle stride or during a strike swing) where natural motion blur masks the frame transition. Use temporary keyframed scale offsets (e.g., briefly scaling a slot to $0.9 imes$ or $1.1 imes$ for 1 frame) to align the boundary pixels of the old and new texture layers perfectly.
2.2 The "Dead Cells" 3D-to-2D Sprite Crunching
Technique
To achieve the fluid motion of 3D combined with the artistic charm of hand-drawn pixel art, we implement a highly stylized 3D animation pipeline:
[High-Poly 3D Model ] ---> [ Flat Emission Shader (Albedo
[ Animation at 60 FPS ] ---> [ Normal-Map Shader (RGB Vec
V
[ Resolution Downscaling ] ---> [ Frame Decimation (10-15 |
1. Low-Resolution Orthographic Render: Models are animated at standard high frame rates (60 FPS) but rendered through an orthographic camera at a highly downscaled target resolution (e.g., $120 imes
120$ pixels per frame).
2. Toon & Emission Shader Setup: Light and shadow are never baked into the raw sprite sheets. In
n١----- L_ __-_
.---..
   9:06
1h
pest-control-ultimate-technical...
109 sources • 13d ago
2. Toon & Emission Shader Setup: Light and shadow are never baked into the raw sprite sheets. In Blender, the shader tree connects the albedo map directly to an Emission Node, bypassing Cycles/ Eevee light shading entirely to deliver clean, unshaded flat colors.
3. Normal Map Rendering (Dynamic Lighting): A second render pass is executed where surface normals (X, Y, Z coordinates) are converted directly into RGB color values: $$ ext{Red} = rac{N_x + 1X2), \quad ext{Green} =
rac{N_y + 1X2}, \quad ext{Blue} =
rac{N_z+ 1K2J$$ This normal map sprite sheet is imported into the game engine, enabling real-time, dynamic pixel-art lighting (e.g., lighting up an ant's shell when a chemical explosion occurs nearby).
4. Frame Decimation (Stop-Motion Aesthetic): To emulate the look of hand-drawn animation, the smooth 60 FPS render is decimated down to 10 to
15 FPS. This step-wise frame progression gives the sprites an organic, retro feel.
5. Color Palette Indexing: Rendered frames pass through a shader that snaps colors to a unified, indexed 32-color palette, eliminating soft gradients and consolidating pixel groupings.
6. Disabling Anti-Aliasing (Freestyle Outlines): To obtain razor-sharp pixel outlines, anti-aliasing must be completely disabled. In Blender, set the Pixel Filter Width to 0.01 with a Box filter. Outlines are generated using Blender's Freestyle line rendering engine set to a 1-pixel constant width.
7. Sub-pixel Movement Avoidance: Ensure that unit movement vectors in-engine are snapped to integer pixel boundaries on the camera grid. Moving a pixel-
8. 9:06
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
:
art character by fractional float values (e.g., 0.3 pixels per frame) causes "sub-pixel shimmering" where individual pixels jump back and forth, breaking the hand-drawn illusion.
SECTION 3: Mathematical
Foundations: Projections, Movement & Combat
3.1 3D Isometric Projection vs. Dimetric 2:1
Projection
An RTS camera requires a clean projection that preserves scale across the map.
True Isometric Projection Matrix
True isometry rotates the coordinate grid horizontally by $45^\circ$ and vertically by $35.264^\circ$, creating exactly $120^lcirc$ angles between the axes. The projection matrix converting 3D coordinates $(X,Y,Z)$ to screen $(U,V)$ is: $$ egin{bmatrix} U \ V lend{bmatrix) =
egin{bmatrix} \cos(45^\circ) & -\sin(45^\circ) & 0 \
Isin(45^lcirc)\sin(35.264^lcirc) & Icos(45^lcirc)
Isin(35.264^lcirc) & -\cos(35.264^lcirc) lend{bmatrix}
egin{bmatrix} X\Y \Z lend{bmatrix}$$ $
$ egin{bmatrix} U \ V lend{bmatrix} = egin{bmatrix)
rac{\sqrt(2)K2} & -
rac{\sqrt(2)K2} &01
rac{\sgrt{6}K6} &
rac{\sqrt{6}6} &-
rac{\sqrt{6}K3} lend{bmatrix} egin{bmatrix} X\Y \Z
lend{bmatrix)$$
The 2:1 Dimetric standard
True isometric projection results in an irrational slope ($ anandiral
9:06
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
True isometric projection results in an irrational slope ($ an(30^lcirc) pprox 0.577$), which creates irregular, jagged pixel step-patterns. To make raster lines clean and symmetrical, we skew the vertical angle to exactly $30^lcirc$, resulting in a perfect 2:1 ratio (lines move 2 pixels horizontally for every 1 pixel vertically): $$ heta = rctan(0.5) pprox 26.565^lcirc$$ The simplified screen
coordinates for our 2:1 tile layout are: $$U = (X - Y) \cdot
rac{W_{ext{tile}}2}$$$$V= (X+Y) lcdot
rac{H_{ext{tile))2} - Z$$
Screen-to-Tile Raycasting (Mouse Clicks)
To find which tile $(Tile_x, Tile_y)$has been clicked given screen coordinates $(U, V)$ (assuming height offset $Z=0$): $$Tile_×=
rac{UKW_{extftile)}) +
rac{VKH_{ext{tile)$$ $$Tile_y =
rac{VKH_{ext(tile))} -
rac{UKW_(ext(tile)))$$
3.2 8-Directional Input Vector Snapping
To translate continuous analog stick or WASD inputs into
8 distinct directional sprite index states (0 = South, 1 =
Southeast, etc.):
1. Calculate the input angle: $\phi = ext{atan2)(y_{
extfinput}}, x_{extfinput}})$
2. Shift the angle by $-45^lcirc$ ($-\pi/4$ radians) to align the inputs with the camera's isometric viewpoint.
3. Snap to the nearest $\pi/4$ increment and wrap into
an index array: $$ ext{Index) = \left\floor
rací\phi -
rac{\piX4}K
rac{\pi{4}} + 0.5 ight floor Ipmod 8$$
9:06
1h
pest-control-ultimate-technical...
109 sources • 13d ago
3.3 Pathfinding: Flow Fields & Flocking (Boids)
Standard $A^*$ pathfinding scales poorly when evaluated individually for 400+ distinct marching ants.
1. Flow Field Pathfinding: We partition the map grid into a static cost field. When a destination is chosen, a single Dijkstra pass generates an integration field pointing toward the goal. This creates a global vector field where each grid tile holds a pre-calculated direction vector. Agents simply lookup their current tile's vector in $O(1)$ constant time.
2. Boids Steering Alignment: To make the insect swarm glide organically through bottlenecks and split around obstacles, we combine the flow field vector with local Boids forces:
• Separation Force: Prevents overlapping. $$
ec{F} ext{sep}} = Isumfj eq i}
rac{
ec(x}_i -
ec{x}_i-
ec{x)_jl^2)$$
• Cohesion Force: Keeps the group moving as a unit. $$
ec{F}{ ext{coh}} = left(
rac{1KN}lsum{j=1}^N
ec(x}_j ight) -
ec{x}_i$$
• Alignment Force: Matches velocities with nearby swarm mates. $$ ec{F} ext{ali}} =
rac{1KN}sum{j=1}^N
ec{v}_i$$
9:07
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
:
3.4 Combat Mathematics & Lanchester's
Formulations
Map architecture dictates combat scaling:
Lanchestera
s Linear Law (Chokepoints &
Stem Networks)
In narrow plant stems where insects must fight one-on-one: $$
rac(dAKdt} = -k_B, Iquad
racídBKdt} = -k_A limplies A_O - A_t =
racík_BHk_AXB_O -B_t$$
• Strategic Outcome: Combat efficiency is directly proportional to individual unit stats (damage, health, armor). This is where heavy, armored beetles excelâ their high stats dominate narrow paths,
rendering the opponent's raw numbers useless.
Lanchesterâ s Square Law (Open Leaves & Canopies)
On wide-open leaf surfaces where all units can focus fire simultaneously: $$
rac{dA}dt} = -k_B Icdot B, Iquad
rac{dB}dt} = -k_A Icdot A limplies k_A(A_0^2 - A_t^2) =
k_B(B_0^2-B_t^2)$$
• Strategic Outcome: Combat efficiency scales quadratically with numbers. A massive swarm of cheap, weak ants will easily overwhelm a small group of expensive, elite beetles once they can surround them and focus fire.
Combat Performance Statistics
• Effective Health (EHP): Measures survivability against physical damage: $$ ext{EHP} =
9:07
1h
pest-control-ultimate-technical...
109 sources • 13d ago
• Effective Health (EHP): Measures survivability against physical damage: $$ extEHP} = rac{ ext{HP}X1 -
rací ext‹Armor}} ext{Armor} + 50}}$$
• Time-to-Kill (TTK): $$ ext{TTK) = \eft \eft\Iceil
rací ext{Target HP}K D_{ D_{ext{base)) -
ext {Armor}) imes M_{ext(carapace)]) ight ceil - 1
ight) imes (ext{Cooldown) + ext(Windup}) +
ext{Windup)$$
SECTION 4: Multiplayer
Synchronization & Netcode
Pest Control operates on a Deterministic Lockstep paradigm with an authoritative Dedicated Game Server
(DGS) to eliminate clients manipulating game memory.
4.1 Client-Side Prediction & Reconciliation
To make gameplay feel instantaneous, the client runs local inputs immediately without waiting for server validation.
Client T_100: Predicts Movement ---> Renders immediately Client T_103: Server Packet arrives stating actual position a Client T_103: 1) Snaps player back to Server T_100 state
2) Re-simulates ticks T_101, T_102, and T_103 in 1 fr
3) Renders corrected present state cleanly
4.2 Server-Side Lag Compensation
When a player fires an ability at a moving target, the server must account for the player's latency. When processing the input, the server rolls back the target's collision volume to the exact historical time the player
initiated the action: $$t_{ext(rewind)} = t_{ext{current))
- left
rac{12) t_{ext(RTT) + t_{extfinterpolation)) ight)$$ The
maximum latency compensated is constrained by the
server's history frame buffer: $$ au_{ext{max)) = N_{
ext‹history_framesh imes left
rac{1000K ext{Tick Rate (Hz)}} ight)$$ With a 16-frame buffer running at a high-performance $120 ext Hz)$ tick rate, the maximum rewound history window is $133.33 ext{ ms)$. Clients with higher pings than this will miss moving targets.
:
SECTION 5: Macroeconomics &
Resource Balancing
Pest Control features a dual-resource model designed to create structural tension between short-term military rushes and long-term economic scalability.
5.1 Resource Types
1. Honeydew (Carbohydrates): Excreted
continuously by herded Aphids grazing on plant sap. Spent on building bases, spawning workers, and advancing technology.
2. Biomass (Proteins): Acquired by capturing immobile Aphid Larvae in contested central map sectors, or by physically consuming your own adult aphids. Spent on hatching combat units and unlocking mutations.
5.2 Cultivation vs. Predation Friction
Players can choose how to leverage their resource nodes:
• Cultivation (Husbandry): Assigning workers to milk aphids for a continuous Honeydew income: $$
ext{Yield)_{ ext{cult)} = lint_0^T R_H(t) dt$$
• Predation (Culling): Executing a target command to davnir an adult anhid divind an inctant maccive
9:07
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
• Predation (Culling): Executing a target command to devour an adult aphid, giving an instant, massive spike of Biomass ($B_{extcull))$) but permanently destroying that aphid.
• The Balancing Threshold: Symmetrical maps are balanced so that the time $T_{ extequilibrium))$ where continuous milking matches a cull spike is set to $2.5 imes$ the time of a standard tier-1 rush.
This ensures that rushing by eating your entire economy is a high-risk, all-in strategy; if the opponent defends the initial push, they gain a massive, irreversible economic advantage.
SECTION 6: Alternative Input: Paper-Based Sketching Controller (Freepad)
To alleviate keyboard-mouse finger fatigue and enhance multitasking, Pest Control supports the Freepad camera-paper controller system.
6.1 Calibration & Computer Vision Pipeline
The setup relies on a standard desktop webcam looking down at a flat sheet of paper.
1. Background Subtraction: On startup, the webcam captures a reference frame of the blank paper. A continuous background subtraction algorithm isolates the player's hand and pen in real-time.
2. Contour Extraction: Using OpenCV, the system detects any dark, closed shapes (squares, circles, triangles) hand-drawn by the player onto the paper:
• It calculates the image moments of the contours to identify the center coordinates of each drawn shape: $$x_{ext{center)) = racM_(10)KM_(00)}, \quad y_{ext(center)) =
9:07
,1h
pest-control-ultimate-technical...
109 sources • 13d ago
down at a flat sheet of paper.
1. Background Subtraction: On startup, the webcam captures a reference frame of the blank paper. A continuous background subtraction algorithm isolates the player's hand and pen in real-time.
2. Contour Extraction: Using OpenCV, the system detects any dark, closed shapes (squares, circles, triangles) hand-drawn by the player onto the paper:
• It calculates the image moments of the contours to identify the center coordinates of each drawn shape: $$x_{ext{center)) = rac{M
_(10)KM_(00)), Iquad y_{extfcenter)) =
rac(M_(01)KM_(00))$$
3. Collision Checking: The system monitors the live feed for when the player's finger or pen-tip enters a contour's boundary (using standard point-in-polygon checks).
6.2 Game Input Mapping
Each drawn shape is mapped to a macro keybinding stream.
• The Multitasking Split: By using their non-dominant hand to tap the paper sheet, players can physically split Conquest and Economy.
Keep the mouse and keyboard focused 100% on micro-managing front-line battles on-screen.
• Tap a hand-drawn circle on the paper pad to execute a background queue macro: Select Base
-> Spawn Worker -> Return Camera. This eliminates screen-flicking and reduces the physical APM requirement of high-level play.
   9:07
,1h
