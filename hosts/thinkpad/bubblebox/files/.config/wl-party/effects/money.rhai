// It rains money: falling bills that burst into coins on expiry
const BILL = "M0 -7 C6 -7 12 -4 12 0 C12 4 6 7 0 7 C-6 7 -12 4 -12 0 C-12 -4 -6 -7 0 -7 Z M-5 0 C-5 3 -2 5 0 5 C2 5 5 3 5 0 C5 -3 2 -5 0 -5 C-2 -5 -5 -3 -5 0 Z";
const DOLLAR = "M0 -10 C4 -6 4 2 3 6 L5 10 L-5 10 L-3 6 C-4 2 -4 -6 0 -10 Z";
const GREENS = ["#85bb65", "#a3d977", "#6ab04c", "#c7f0a8"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = ctx.height * 0.25;
    ctx.drag = 0.9;
    for i in 0..ctx.count / 3 {
        ctx.emit(#{
            x: rand() * ctx.width,
            y: -30.0 - rand() * ctx.height * 0.5,
            vx: (rand() - 0.5) * 120.0,
            vy: ctx.height * 0.05,
            fuse: 2.0 + rand() * 1.5,
            shape: BILL,
            size: 30.0 + rand() * 12.0,
            color: pick(GREENS),
            wobble: 10.0 + rand() * 10.0,
            tag: "bill",
        });
    }
}

fn expire(ctx, p) {
    if p.tag != "bill" { return; }
    // each bill bursts into golden coins
    let coins = 6 + (rand() * 4.0).to_int();
    for i in 0..coins {
        let angle = 2.0 * PI() * i / coins + rand() * 0.5;
        let speed = 120.0 + rand() * 160.0;
        ctx.emit(#{
            x: p.x, y: p.y,
            vx: p.vx * 0.5 + angle.cos() * speed,
            vy: angle.sin() * speed - 60.0,
            fuse: 1.6 + rand() * 0.8,
            shape: "circle",
            size: 10,
            color: "#ffd700",
            shadow: "#7a5c00",
            spin: false,
        });
    }
}
