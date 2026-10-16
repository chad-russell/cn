// Hearts bubble up from the bottom, then pop into mini-hearts
const HEART = "M0 3 C0 3 -6 -1 -6 -5 C-6 -8 -3 -9 0 -6 C3 -9 6 -8 6 -5 C6 -1 0 3 0 3 Z";
const PINKS = ["#ff4d6d", "#ff7ac8", "#ff9ec4", "#ffd9f2"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = -ctx.height * 0.03;
    ctx.drag = 0.35;
    for i in 0..ctx.count / 4 {
        ctx.emit(#{
            x: rand() * ctx.width,
            y: ctx.height + 40.0 + rand() * ctx.height * 0.5,
            vx: (rand() - 0.5) * 40.0,
            vy: -ctx.height * (0.12 + rand() * 0.06),
            fuse: 1.8 + rand() * 1.6,
            shape: HEART,
            size: 26.0 + rand() * 22.0,
            color: pick(PINKS),
            wobble: 14.0 + rand() * 10.0,
            tag: "big",
        });
    }
}

fn expire(ctx, p) {
    if p.tag != "big" { return; }
    let n = 6 + (rand() * 4.0).to_int();
    for i in 0..n {
        let angle = 2.0 * PI() * i / n;
        ctx.emit(#{
            x: p.x, y: p.y,
            vx: angle.cos() * 130.0 + p.vx,
            vy: angle.sin() * 130.0 + p.vy,
            fuse: 1.0 + rand(),
            shape: HEART,
            size: 12,
            color: p.color,
            spin: false,
        });
    }
}
