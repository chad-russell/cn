use owo_colors::OwoColorize;
use std::io::IsTerminal;
use std::time::{Duration, SystemTime, UNIX_EPOCH};

#[derive(Clone, Copy)]
pub(super) enum InspectStatus {
    Defined,
    Prepared,
}

pub(super) fn inspect_status(built_live: bool) -> InspectStatus {
    if built_live {
        InspectStatus::Prepared
    } else {
        InspectStatus::Defined
    }
}

pub(super) fn colors_enabled() -> bool {
    std::io::stdout().is_terminal()
        && std::env::var_os("NO_COLOR").is_none()
        && std::env::var("TERM").map(|v| v != "dumb").unwrap_or(true)
}

pub(super) fn style_title(value: &str, colors: bool) -> String {
    if colors {
        value.bold().to_string()
    } else {
        value.to_string()
    }
}

pub(super) fn style_label(value: &str, colors: bool) -> String {
    if colors {
        value.blue().bold().to_string()
    } else {
        value.to_string()
    }
}

pub(super) fn style_action(value: &str, colors: bool) -> String {
    if colors {
        format!("{} {}", "✓".green().bold(), value.green().bold())
    } else {
        format!("✓ {value}")
    }
}

pub(super) fn style_section(value: &str, colors: bool) -> String {
    if colors {
        value.bright_black().bold().to_string()
    } else {
        value.to_string()
    }
}

pub(super) fn style_status_badge(status: InspectStatus, colors: bool) -> String {
    match status {
        InspectStatus::Defined => {
            if colors {
                format!("{} {}", "●".yellow().bold(), "defined".yellow().bold())
            } else {
                "* defined".to_string()
            }
        }
        InspectStatus::Prepared => {
            if colors {
                format!("{} {}", "●".blue().bold(), "prepared".blue().bold())
            } else {
                "* prepared".to_string()
            }
        }
    }
}

pub(super) fn style_bool(value: bool, colors: bool) -> String {
    match (value, colors) {
        (true, true) => format!("{} {}", "✓".green().bold(), "yes".green()),
        (false, true) => format!("{} {}", "✗".red().bold(), "no".red()),
        (true, false) => "yes".to_string(),
        (false, false) => "no".to_string(),
    }
}

pub(super) fn style_recorded_state(recorded: bool, live: bool, colors: bool) -> String {
    let summary = if recorded == live {
        style_bool(live, colors)
    } else if colors {
        format!("{} {}", "!".yellow().bold(), "drift".yellow().bold())
    } else {
        "drift".to_string()
    };
    format!(
        "{summary}  {} {}  {} {}",
        style_section("recorded", colors),
        style_bool(recorded, colors),
        style_section("live", colors),
        style_bool(live, colors)
    )
}

pub(super) fn format_last_built_at(raw: Option<&str>) -> String {
    let Some(raw) = raw else {
        return "never".to_string();
    };
    let Ok(secs) = raw.parse::<u64>() else {
        return raw.to_string();
    };
    let timestamp = UNIX_EPOCH + Duration::from_secs(secs);
    let absolute = humantime::format_rfc3339_seconds(timestamp).to_string();
    let relative = match SystemTime::now().duration_since(timestamp) {
        Ok(delta) => format!("{} ago", humantime::format_duration(delta)),
        Err(_) => absolute.clone(),
    };
    format!("{absolute} ({relative})")
}
