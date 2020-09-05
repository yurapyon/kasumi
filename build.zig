const Builder = @import("std").build.Builder;

pub fn build(b: *Builder) void {
    const target = b.standardTargetOptions(.{});
    const mode = b.standardReleaseOptions();

    var tests = b.addTest("src/main.zig");
    tests.setBuildMode(mode);

    tests.addLibPath("/usr/lib");
    tests.addIncludeDir("/usr/include");
    tests.linkSystemLibrary("c");
    tests.linkSystemLibrary("portaudio");
    tests.addPackagePath("nitori", "lib/nitori/src/main.zig");

    const test_step = b.step("test", "Run tests");
    test_step.dependOn(&tests.step);

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
