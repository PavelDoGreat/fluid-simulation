const std = @import("std");
// const sokol = @import("sokol");
// const shdc = @import("shdc");

/// Command to run debug
//~ zig build run

/// Command to run optimized build
//~ zig build --release=fast run

/// You can add --watch to always build on code changes. Very convenient btw.

/// This is for building web version
//~ zig build -Dtarget=wasm32-freestanding -p projects/web --watch
/// Then run local server and open in web browser http://localhost:1369/
//~ python3 -m http.server 1369 --directory projects/web

/// Just left over for the future
// --release=small --release=safe  wasm32-freestanding wasm32-wasi wasm32-emscripten
// --verbose

pub fn build (b: *std.Build) !void
{
    const target = b.standardTargetOptions(.{});
    const optimize = b.standardOptimizeOption(.{});

    //const target = b.resolveTargetQuery(.{ .os_tag = .macos });
    //const target = b.resolveTargetQuery(.{ .os_tag = .windows });
    //const target = b.resolveTargetQuery(.{ .os_tag = .linux });

    if (target.result.cpu.arch.isWasm())
    {
        const exe = b.addExecutable(.{
            .name = "fluid",
            .target = target,
            .optimize = .ReleaseSmall, // .Debug .ReleaseFast
            .root_source_file = b.path("src/fluid/main.zig"),
        });
        exe.entry = .disabled;
        exe.rdynamic = true;

        // exe.root_module.export_symbol_names

        addCommonImports(b, exe.root_module);
        b.installArtifact(exe);
    }
    else if (target.result.os.tag == .macos)
    {
        // try std.fs.cwd().makePath("zig-out/metal/");
        try std.fs.cwd().makePath("zig-out/lib/");

        const exe = b.addExecutable(.{
            .name = "fluid",
            .target = target,
            .optimize = optimize,
            .root_source_file = b.path("src/fluid/main.zig"),
            // .root_module = exe_mod,
            // .single_threaded = true,
            // .strip = true,
            // .omit_frame_pointer = false,
            // .unwind_tables = .none,
            // .error_tracing = false
        });
        // exe.entry = .{ .symbol_name = "init" };

        const cmd_metalir = b.addSystemCommand(&.{
            "xcrun", "-sdk", "macosx", "metal",
            "-o", "zig-out/bin/shader.ir",
            "-c", "src/fluid/shaders/shader.metal",
        });

        const cmd_metallib = b.addSystemCommand(&.{
            "xcrun", "-sdk", "macosx", "metallib",
            "-o", "zig-out/bin/shader.metallib",
            "zig-out/bin/shader.ir",
        });
        // cmd_metal.addCheck(.{ .expect_term = .{ .Exited = 0 } });
        // cmd_metal.has_side_effects = true;

        const cmd_objc = b.addSystemCommand(&.{
            "clang",
            // "-O3",
            "-o", "zig-out/lib/cocoa_osx.o",
            "-c", "src/engine/darwin/cocoa_osx.mm",
            // "-framework", "Cocoa",
        });
        // cmd_objc.setCwd(b.path("src"));
        cmd_objc.addCheck(.{ .expect_term = .{ .Exited = 0 } });
        cmd_objc.has_side_effects = true;

        // const cmd_swift = b.addSystemCommand(&.{
        //     "xcrun", "swiftc",
        //     "-emit-object",
        //     // "-parse-as-library",
        //     // "-target-cpu" // for the future
        //     "-I", "src/engine/darwin/",
        //     // "-cxx-interoperability-mode=default",
        //     "-o", "zig-out/lib/cocoa_osx.o",
        //     "src/engine/darwin/cocoa_osx.swift"
        // });

        cmd_metallib.step.dependOn(&cmd_metalir.step);
        exe.step.dependOn(&cmd_metallib.step);
        exe.step.dependOn(&cmd_objc.step);
        // exe.step.dependOn(&cmd_swift.step);

        // main_exe.linkLibC();
        // main_exe.linkLibCpp();
        // main_exe.linkFramework("Foundation");

        exe.linkFramework("Foundation");
        exe.linkFramework("Cocoa");
        exe.linkFramework("Metal");
        exe.linkFramework("QuartzCore");

        exe.addObjectFile(b.path("zig-out/lib/cocoa_osx.o"));

        // main_exe.addLibraryPath(std.Build.LazyPath {
        //     .cwd_relative = "/Applications/Xcode.app/Contents/Developer/Toolchains/XcodeDefault.xctoolchain/usr/lib/swift/macosx",
        // });
        // main_exe.linkSystemLibrary("swiftCore");

        // lib.installHeadersDirectory(b.path("src"), "", .{});
        // exe.addIncludeDir("/usr/local/include/SDL2");
        // exe.addLibPath("/usr/local/lib");
        
        // main_exe.addFrameworkPath(b.path("/Applications/Xcode.app/Contents/Developer/Platforms/MacOSX.platform/Developer/SDKs/MacOSX.sdk/System/Library/Frameworks"));
        // main_exe.addIncludePath(lazy_path: LazyPath)

        addCommonImports(b, exe.root_module);
        b.installArtifact(exe);

        const run = b.addRunArtifact(exe);
        run.step.dependOn(b.getInstallStep());
        b.step("run", "Run the app").dependOn(&run.step);
    }
}

fn addCommonImports (b: *std.Build, root_module: *std.Build.Module) void
{
    const app = b.createModule(.{ .root_source_file = b.path("src/engine/application.zig") });
    const native = b.createModule(.{ .root_source_file = b.path("src/engine/native.zig") });
        // native.addImport("app", app);
    const debug = b.createModule(.{ .root_source_file = b.path("src/engine/debug.zig") });
        // debug.addImport("app", app);
    const files = b.createModule(.{ .root_source_file = b.path("src/engine/files.zig") });
        // files.addImport("app", app);
        // files.addImport("debug", debug);

    importModulesToEachOtherAndToRoot(root_module, &.{
        .{ .name = "app", .module = app },
        .{ .name = "native", .module = native },
        .{ .name = "debug", .module = debug },
        .{ .name = "files", .module = files },
    });

    // root_module.addImport("app", app);
    // root_module.addImport("native", native);
    // root_module.addImport("debug", debug);
    // root_module.addImport("files", files);

    // module.addAnonymousImport("utils", "src/utils.zig");
}

fn importModulesToEachOtherAndToRoot (root_module: *std.Build.Module, modules: []const struct { name: []const u8, module: *std.Build.Module }) void
{
    for (modules) |group|
    {
        for (modules) |tuple|
        {
            if (group.module != tuple.module)
                group.module.addImport(tuple.name, tuple.module);
        }
    }

    for (modules) |tuple|
        root_module.addImport(tuple.name, tuple.module);
}

    // const dep_sokol = b.dependency("sokol", .{
    //     .target = target,
    //     .optimize = optimize,
    // });

    // const exe_mod = b.createModule(.{
    //     .root_source_file = b.path("src/main.zig"),
    //     .target = target,
    //     .optimize = optimize,
    //     // .imports = &.{
    //     //     .{ .name = "sokol", .module = dep_sokol }
    //     // }
    //     // .unwind_tables = .none,
    //     // .strip = true
    // });
    // exe_mod.addImport("sokol", dep_sokol.module("sokol"));

    // if (target.result.cpu.arch.isWasm())
    // {
    //     // const opt_shd_step = try buildShaders(b);

    //     const main = b.addStaticLibrary(.{
    //         .name = "fluid",
    //         .target = target,
    //         .optimize = optimize,
    //         .root_source_file = b.path("src/main.zig"),
    //     });
    //     main.root_module.addImport("sokol", dep_sokol.module("sokol"));

    //     // if (opt_shd_step) |shd_step|
    //     //     main.step.dependOn(&shd_step.step);

    //     // Emscripten linker
    //     const emsdk = dep_sokol.builder.dependency("emsdk", .{});
    //     const link_step = try sokol.emLinkStep(b, .{
    //         .lib_main = main,
    //         .target = target,
    //         .optimize = optimize,
    //         .emsdk = emsdk,
    //         .use_webgpu = false,
    //         .use_webgl2 = true,
    //         .use_emmalloc = true,
    //         .use_filesystem = false,
    //         // .use_offset_converter = true,
    //         // .extra_args = &.{"-sSTACK_SIZE=512KB"},
    //         .shell_file_path = dep_sokol.path("src/sokol/web/shell.html"),
    //         // // don't run Closure minification for WebGPU, see: https://github.com/emscripten-core/emscripten/issues/20415
    //         // .release_use_closure = options.backend != .wgpu,
    //     });
    //     b.getInstallStep().dependOn(&link_step.step);

    //     // sokol.sha

    //     const run = sokol.emRunStep(b, .{ .name = "fluid", .emsdk = emsdk });
    //     run.addArg("--no_browser"); // comment this line if you want it to focus on web browser after build
    //     run.step.dependOn(&link_step.step);
    //     b.step("run", "Run fluid web").dependOn(&run.step);
    // }



    // const exe_check = b.addExecutable(.{
    //     .name = "fluid",
    //     .root_source_file = b.path("src/main.zig"),
    // });

    // const check = b.step("check", "Check if fluid compiles");
    // check.dependOn(&exe_check.step);



// fn buildShaders (b: *std.Build) !?*std.Build.Step.Run
// {
//     // if (!example.has_shader)
//     //     return null;

//     const shaders_dir = "src/shaders/";
//     const input_path = b.fmt("{s}{s}.glsl", .{ shaders_dir, "fluid" });
//     const output_path = b.fmt("{s}{s}.glsl.zig", .{ shaders_dir, "fluid" });
//     return try shdc.compile(b, .{
//         .dep_shdc = b.dependency("shdc", .{}),
//         .input = b.path(input_path),
//         .output = b.path(output_path),
//         .slang = .{
//             // .glsl430 = example.needs_compute,
//             // .glsl410 = !example.needs_compute,
//             // .glsl310es = example.needs_compute,
//             .glsl300es = true,
//             .metal_macos = true,
//             // .hlsl5 = true,
//             // .wgsl = true,
//         },
//         .reflection = true,
//     });
// }