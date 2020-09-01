const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    const exe = b.addExecutable("kasumi", "src/main.zig");
    exe.setTarget(target);
    exe.setBuildMode(mode);

    exe.addLibPath("/usr/lib");
    exe.addIncludeDir("/usr/include");
    exe.linkSystemLibrary("c");
    exe.linkSystemLibrary("portaudio");
    exe.addPackagePath("nitori", "lib/nitori/src/main.zig");

    exe.install();

    const run_cmd = exe.run();
    run_cmd.step.dependOn(b.getInstallStep());

    const run_step = b.step("run", "Run the app");
    run_step.dependOn(&run_cmd.step);
}
