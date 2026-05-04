const z = @import("zephyr.zig");

pub const Level = enum(u8) {
    trace = 0,
    debug = 1,
    info = 2,
    warn = 3,
    err = 4,
    critical = 5,
    off = 255,

    pub fn to_str(self: Level) []const u8 {
        return switch (self) {
            .trace => "TRACE",
            .debug => "DEBUG",
            .info => "INFO",
            .warn => "WARN",
            .err => "ERROR",
            .critical => "CRITICAL",
            .off => "OFF",
        };
    }
};

pub const Config = struct {
    module_name: []const u8,
    compile_level: Level = .debug, 
    runtime_level: Level = .debug, 
    show_timestamp: bool = true,
    show_module: bool = true,
    colors: bool = false,
};

pub fn Logger(comptime cfg: Config) type {
    return struct {
        const Self = @This();

        pub var runtime_level: Level = cfg.runtime_level;

        fn enabled(comptime level: Level) bool {
            return @intFromEnum(level) >= @intFromEnum(cfg.compile_level) and
                @intFromEnum(level) >= @intFromEnum(runtime_level);
        }

        fn color(comptime level: Level) []const u8 {
            if (!cfg.colors) return "";

            return switch (level) {
                .trace => "\x1b[90m",
                .debug => "\x1b[36m",
                .info  => "\x1b[32m",
                .warn  => "\x1b[33m",
                .err   => "\x1b[31m",
                .critical => "\x1b[1;31m",
                .off   => "",
            };
        }

        fn reset() []const u8 {
            return if (cfg.colors) "\x1b[0m" else "";
        }

        pub fn setLevel(level: Level) void {
            runtime_level = level;
        }

        pub fn log(
            comptime level: Level,
            comptime fmt: []const u8,
            args: anytype,
        ) void {
            if (!enabled(level)) return;

            const prefix_args = .{ z.uptimeGet(), cfg.module_name, level.to_str() };

            if (cfg.show_timestamp and cfg.show_module) {
                z.printk(color(level) ++ "[{} ms] [{s}] [{s}] " ++ fmt ++ reset() ++ "\n", prefix_args ++ args);
            } else if (cfg.show_timestamp) {
                z.printk(color(level) ++ "[{} ms] [{s}] " ++ fmt ++ reset() ++ "\n", .{ z.uptimeGet(), level.to_str() } ++ args);
            } else if (cfg.show_module) {
                z.printk(color(level) ++ "[{s}] [{s}] " ++ fmt ++ reset() ++ "\n", .{ cfg.module_name, level.to_str() } ++ args);
            } else {
                z.printk(color(level) ++ "[{s}] " ++ fmt ++ reset() ++ "\n", .{ level.to_str() } ++ args);
            }
        }

        pub inline fn trace(comptime fmt: []const u8, args: anytype) void {
            log(.trace, fmt, args);
        }

        pub inline fn debug(comptime fmt: []const u8, args: anytype) void {
            log(.debug, fmt, args);
        }

        pub inline fn info(comptime fmt: []const u8, args: anytype) void {
            log(.info, fmt, args);
        }

        pub inline fn warn(comptime fmt: []const u8, args: anytype) void {
            log(.warn, fmt, args);
        }

        pub inline fn err(comptime fmt: []const u8, args: anytype) void {
            log(.err, fmt, args);
        }

        pub inline fn critical(comptime fmt: []const u8, args: anytype) void {
            log(.critical, fmt, args);
        }

        pub fn hexdump(comptime level: Level, label: []const u8, data: []const u8) void {
            if (!enabled(level)) return;

            z.printk(color(level) ++ "[{s}] " ++ "{s}: {} bytes" ++ reset() ++ "\n", .{ level.to_str(), label, data.len });

            var i: usize = 0;
            while (i < data.len) : (i += 16) {
                const end = @min(i + 16, data.len);

                z.printk("  {x:0>4}: ", .{ i });

                for (data[i..end]) |b| {
                    z.printk("{x:0>2} ", .{ b });
                }

                z.printk("\n", .{});
            }
        }
    };
}
