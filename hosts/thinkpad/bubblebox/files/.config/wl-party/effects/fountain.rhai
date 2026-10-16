// A center fountain: glitter jets upward, sparkle shadow on light backgrounds
const GOLD = ["#ffd700", "#fff2b2", "#ffb347"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = ctx.height * 0.5;
    ctx.drag = 1.0;
    let cx = ctx.width / 2.0;
    for i in 0..ctx.count {
        // narrow nozzle spread, wide speed variance => layered spray
        let angle = PI() / 2.0 + (rand() - 0.5) * 0.5;
        let speed = ctx.height * (0.55 + rand() * 0.45);
        ctx.emit(#{
            x: cx + (rand() - 0.5) * 40.0,
            y: ctx.height,
            vx: angle.cos() * speed,
            vy: -angle.sin() * speed,
            fuse: 1.6 + rand() * 1.2,
            shape: "circle",
            size: 4.0 + rand() * 4.0,
            color: pick(GOLD),
            shadow: "#6b4a00",
            spin: false,
        });
    }
}
