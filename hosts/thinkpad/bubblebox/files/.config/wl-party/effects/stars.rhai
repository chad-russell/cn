// Twinkling stars fade in across the sky, then shoot away as streaks
const STAR = "M0 -10 L2.4 -2.4 L10 0 L2.4 2.4 L0 10 L-2.4 2.4 L-10 0 L-2.4 -2.4 Z";
const COLORS = ["#ffffff", "#fff2b2", "#bfe7ff", "#ffd9f2"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = 0.0;
    ctx.drag = 0.0;
    for i in 0..ctx.count {
        ctx.emit(#{
            x: rand() * ctx.width,
            y: rand() * ctx.height,
            fuse: 0.5 + rand() * 2.5,
            shape: STAR,
            size: 6.0 + rand() * 10.0,
            color: pick(COLORS),
            shadow: "#1a2b4a",
            spin: false,
            tag: "twinkle",
        });
    }
}

fn expire(ctx, p) {
    // ~1 in 3 stars becomes a shooting star streaking off-screen
    if rand() < 0.33 {
        let angle = (rand() - 0.5) * PI() * 0.6 + PI(); // aim leftward-ish
        let speed = ctx.width * (0.5 + rand() * 0.4);
        ctx.emit(#{
            x: p.x, y: p.y,
            vx: angle.cos() * speed,
            vy: angle.sin() * speed,
            fuse: 0.8,
            shape: "circle", size: 7,
            color: p.color,
            spin: false,
            tag: "streak",
        });
    }
}
