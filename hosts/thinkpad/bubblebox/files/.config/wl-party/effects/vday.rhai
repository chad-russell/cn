// A slow warm snowfall of tiny hearts
const HEART = "M0 3 C0 3 -6 -1 -6 -5 C-6 -8 -3 -9 0 -6 C3 -9 6 -8 6 -5 C6 -1 0 3 0 3 Z";
const PINKS = ["#ff4d6d", "#ff7ac8", "#ffb3c6", "#ffffff"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = 40.0;
    ctx.drag = 0.6;
    for i in 0..ctx.count {
        ctx.emit(#{
            x: rand() * ctx.width,
            y: -20.0 - rand() * ctx.height,
            vx: (rand() - 0.5) * 30.0,
            vy: 60.0 + rand() * 50.0,
            shape: HEART,
            size: 10.0 + rand() * 16.0,
            color: pick(PINKS),
            shadow: "#5c1a2e",
            spin: false,
            wobble: 12.0 + rand() * 20.0,
        });
    }
}
