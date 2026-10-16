// Digital rain: glyphs fall in columns, dissolve into static sparks
const GLYPH = "M-3 -8 L3 -8 L3 8 L-3 8 Z M-3 -8 L3 8 M3 -8 L-3 8 M-6 0 L6 0 M0 -11 L0 11";
const GREENS = ["#00ff66", "#33ff99", "#66ffc2", "#ccffdd"];

fn pick(list) { list[(rand() * list.len()).to_int()] }

fn start(ctx) {
    ctx.gravity = 0.0;
    ctx.drag = 0.0;
    let columns = 24;
    let per_col = ctx.count / columns;
    for c in 0..columns {
        let x = ctx.width * (c + 0.5) / columns;
        let speed = ctx.height * (0.35 + rand() * 0.3);
        let head = -20.0 - rand() * ctx.height * 0.3; // column head start
        for i in 0..per_col {
            ctx.emit(#{
                x: x + (rand() - 0.5) * 4.0,
                y: head - i * 26.0, // trailing glyphs above the head
                vx: 0.0,
                vy: speed,
                fuse: (ctx.height + 40.0 - (head - i * 26.0)) / speed,
                shape: GLYPH,
                size: 14.0 + rand() * 8.0,
                color: if i == 0 { "#eaffea" } else { pick(GREENS) },
                shadow: "#003311",
                spin: false,
            });
        }
    }
}

fn expire(ctx, p) { }
