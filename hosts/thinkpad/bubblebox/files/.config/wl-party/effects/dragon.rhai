// A glowing serpent undulates across the screen, then dissolves into embers
const SEG = "M0 -6 C5 -6 8 0 6 4 L0 8 L-6 4 C-8 0 -5 -6 0 -6 Z";
const EMBER = ["#ffb347", "#ff6b35", "#ffd700", "#ff4d6d"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = 0.0;
    ctx.drag = 0.55;
    let n = ctx.count;
    for i in 0..n {
        let t = i / n; // 0..1 along the body
        ctx.emit(#{
            // Sine-wave path from left edge to right edge
            x: ctx.width * (-0.05 + 1.15 * t),
            y: ctx.height * (0.45 + 0.22 * (3.0 * PI() * t + 1.2).sin()),
            vx: ctx.width * 0.22 * (0.9 + 0.2 * (1.0 - t)),
            vy: ctx.width * 0.22 * 0.66 * (3.0 * PI() * t + 1.2).cos() * 3.0 * PI() / n * n,
            fuse: 0.5 + 2.6 * t,
            shape: SEG,
            size: 34.0 * (1.0 - 0.55 * t),
            color: if t < 0.2 { "#ffe066" } else { "#ff6b35" },
            shadow: "#5a1a00",
            spin: false,
            tag: "body",
        });
    }
    // sparks trail behind the dragon's head (first = largest size ... reversed below)
}

fn expire(ctx, p) {
    if p.tag != "body" { return; }
    // Each segment dissolves into a few embers that drift and fade
    if rand() < 0.6 {
        ctx.emit(#{
            x: p.x, y: p.y,
            vx: (rand() - 0.5) * 60.0,
            vy: -30.0 - rand() * 50.0,
            fuse: 1.2 + rand() * 1.2,
            shape: "circle",
            size: 5,
            color: pick(EMBER),
            spin: false,
            tag: "ember",
        });
    }
}
