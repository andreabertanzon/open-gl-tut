const std = @import("std");
const c = @cImport({
    @cInclude("glad.h");
    @cInclude("SDL.h");
    @cInclude("SDL_image.h");
});
const print = std.debug.print;

const gScreenHeight = 480;
const gScreenWidth = 640;

var gGraphicsApplicationWindow: *c.SDL_Window = undefined;
var gOpenGLContext: c.SDL_GLContext = undefined;
var gQuit = false;

/// VAO
var gVertexArrayObject: c.GLuint = 0;

/// VBO
var gVertexBufferObject: c.GLuint = 0;

/// Program Object for shader
var gGraphicsPipelineShaderProgram: c.GLuint = 0;

var gFragmentShaderSource: []const u8 = "#version 460 core\nout vec4 color;\nvoid main()\n{\n    color = vec4(1.0f, 0.5f, 0.0f, 1.0f);\n}\n";
var gVertexShaderSource: []const u8 = "#version 460 core\nin vec4 position;\nvoid main()\n{\n   gl_Position = vec4(position.x, position.y, position.z, position.w);\n}\n";
///initializing attributes
pub fn initializeSdlGlAttributes() !void {
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MAJOR_VERSION, 4);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_MINOR_VERSION, 6);
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_CONTEXT_PROFILE_MASK, c.SDL_GL_CONTEXT_PROFILE_CORE);
    //Setting double buffering
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DOUBLEBUFFER, 1);
    // setting precision
    _ = c.SDL_GL_SetAttribute(c.SDL_GL_DEPTH_SIZE, 24);
}
pub fn vertexSpecification() !void {
    const vertexPosition: [9]f32 = [_]f32{ -0.8, -0.8, 0.0,
                                            0.8, -0.8, 0.0, 
                                            0.0, 0.8, 0.0 };

    c.glGenVertexArrays(1, &gVertexArrayObject);
    c.glBindVertexArray(gVertexArrayObject);

    // start VBO
    c.glGenBuffers(1, &gVertexBufferObject);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, gVertexBufferObject);
    c.glBufferData(c.GL_ARRAY_BUFFER, vertexPosition.len * @sizeOf(@TypeOf(vertexPosition)), &vertexPosition, c.GL_STATIC_DRAW);

    c.glEnableVertexAttribArray(0); // enables the posision attribute
    c.glVertexAttribPointer(0, 3, c.GL_FLOAT, c.GL_FALSE, 0, null);

    // CLEANUP
    c.glBindVertexArray(0);
    // c.glDisableVertexAttribArray(0);
}

fn glDebugOutput(_: c_uint, _: c_uint, _: c_uint, severity: c_uint, length: c_int, message: [*c]const u8, _: ?*const anyopaque) callconv(.C) void {
    if(severity == c.GL_DEBUG_SEVERITY_HIGH) { // TODO: Capture the stack traces.
        std.log.err("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
    } else if(severity == c.GL_DEBUG_SEVERITY_MEDIUM) {
        std.log.warn("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
    } else if(severity == c.GL_DEBUG_SEVERITY_LOW) {
        std.log.info("OpenGL {}:{s}", .{severity, message[0..@intCast(usize, length)]});
    }
}

pub fn compile_shader(shaderType: c.GLuint, sourceCode: *[]const u8) !c.GLuint {
    var shaderObject: c.GLuint = 0;
    if (shaderType == c.GL_VERTEX_SHADER) {
        shaderObject = c.glCreateShader(c.GL_VERTEX_SHADER);
    } else {
        shaderObject = c.glCreateShader(c.GL_FRAGMENT_SHADER);
    }
    var c_src = [_][*]const u8{sourceCode.ptr};
    var c_len = [_]i32{@intCast(i32, sourceCode.len)};
    // c.glShaderSource(shaderObject, 1, &c_src, &c_len);
    c.glShaderSource(shaderObject, 1, &c_src, &c_len);
    c.glCompileShader(shaderObject);

    var success: i32 = undefined;
    var log: [512]u8 = undefined;
    c.glGetShaderiv(shaderObject, c.GL_COMPILE_STATUS, &success);
    if (success == 0) {
        c.glGetShaderInfoLog(shaderObject, 512, null, &log);
        print("shader log: {s}\n", .{log});
        // return 0;
    }
    return shaderObject;
}

pub fn create_shader_program(vertexShaderSource: *[]const u8, fragmentShaderSource: *[]const u8) !c.GLuint {
    var programObject: c.GLuint = c.glCreateProgram();

    var myVertexShader: c.GLuint = try compile_shader(c.GL_VERTEX_SHADER, vertexShaderSource);
    var myFragmentShader: c.GLuint = try compile_shader(c.GL_FRAGMENT_SHADER, fragmentShaderSource);

    c.glAttachShader(programObject, myVertexShader);
    c.glAttachShader(programObject, myFragmentShader);
    c.glLinkProgram(programObject);

    c.glValidateProgram(programObject);
    var success: i32 = undefined;
    var log: [512]u8 = undefined;
    c.glGetProgramiv(programObject, c.GL_LINK_STATUS, &success);
    if (success == 0) {
        c.glGetShaderInfoLog(programObject, 512, null, &log);
        print("Linking shader:{s}", .{log});
        //@panic("error linking shader");
    }
    return programObject;
}

pub fn create_graphics_pipeline() !void {
    print("shaderVertex:\n{s}\nshaderFragment:{s}\n", .{ gVertexShaderSource, gFragmentShaderSource });
    gGraphicsPipelineShaderProgram = try create_shader_program(&gVertexShaderSource, &gFragmentShaderSource);
}

/// initialization of SDL
pub fn initialize_program() !void {
    if (c.SDL_Init(c.SDL_INIT_VIDEO) < 0) {
        print("SDL2 could not initialize the video subsystem", .{});
        @panic("critical error initializing SDL");
    }

    initializeSdlGlAttributes() catch |e| {
        print("error initializing SDL_Attributes", .{});
        @panic(@errorName(e));
    };

    // Setting the Window
    gGraphicsApplicationWindow = c.SDL_CreateWindow("OpenGL", 0, 0, gScreenWidth, gScreenHeight, c.SDL_WINDOW_OPENGL) orelse {
        @panic("error creating Window");
    };
    // setting openGL's context
    gOpenGLContext = c.SDL_GL_CreateContext(gGraphicsApplicationWindow);
    if (c.gladLoadGLLoader(@as(c.GLADloadproc, c.SDL_GL_GetProcAddress)) < 1) {
        print("ERROR:", .{});
    }

    _ = c.SDL_GL_MakeCurrent(gGraphicsApplicationWindow, gOpenGLContext);
     
    c.glEnable(c.GL_DEBUG_OUTPUT);
    c.glEnable(c.GL_DEBUG_OUTPUT_SYNCHRONOUS);
    c.glDebugMessageCallback(glDebugOutput, null);
    c.glDebugMessageControl(c.GL_DONT_CARE, c.GL_DONT_CARE, c.GL_DONT_CARE, 0, null, c.GL_TRUE);

    print("Vendor:    {s}\n", .{c.glGetString(c.GL_VENDOR)});
    print("Renderer:  {s}\n", .{c.glGetString(c.GL_RENDERER)});
    print("Version:   {s}\n", .{c.glGetString(c.GL_VERSION)});
    print("ShdingLan: {s}\n", .{c.glGetString(c.GL_SHADING_LANGUAGE_VERSION)});
}

pub fn input() !void {
    var event: c.SDL_Event = undefined;

    while (c.SDL_PollEvent(&event) != 0) {
        if (event.type == c.SDL_QUIT) {
            print("BYE!", .{});
            gQuit = true;
        }
    }
}

/// sets openGL state
pub fn pre_draw() !void {
    c.glDisable(c.GL_DEPTH_TEST);
    c.glDisable(c.GL_CULL_FACE);
    c.glViewport(0, 0, gScreenWidth, gScreenHeight);
    c.glClearColor(1.0, 1.0, 0.0, 1.0);
    c.glClear(c.GL_DEPTH_BUFFER_BIT | c.GL_COLOR_BUFFER_BIT);
    c.glUseProgram(gGraphicsPipelineShaderProgram);
}

pub fn draw() !void {
    c.glBindVertexArray(gVertexArrayObject);
    c.glBindBuffer(c.GL_ARRAY_BUFFER, gVertexBufferObject);

    c.glDrawArrays(c.GL_TRIANGLES, 0, 3);
}

pub fn main_loop() !void {
    while (!gQuit) {
        try input();

        try pre_draw();

        try draw();

        c.SDL_GL_SwapWindow(gGraphicsApplicationWindow);
    }
}

pub fn clean_up() !void {
    c.SDL_DestroyWindow(gGraphicsApplicationWindow);
    c.SDL_Quit();
}

pub fn main() !void {
    try initialize_program();

    try vertexSpecification();

    try create_graphics_pipeline();

    try main_loop();

    try clean_up();
}

test "simple test" {
    var list = std.ArrayList(i32).init(std.testing.allocator);
    defer list.deinit(); // try commenting this out and see if zig detects the memory leak!
    try list.append(42);
    try std.testing.expectEqual(@as(i32, 42), list.pop());
}
