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
    c.glDisableVertexAttribArray(0);
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

pub fn compileShader(shaderType: c.GLuint, sourceCode: *[]const u8) !c.GLuint {
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

pub fn createShaderProgram(vertexShaderSource: *[]const u8, fragmentShaderSource: *[]const u8) !c.GLuint {
    var programObject: c.GLuint = c.glCreateProgram();

    var myVertexShader: c.GLuint = try compileShader(c.GL_VERTEX_SHADER, vertexShaderSource);
    var myFragmentShader: c.GLuint = try compileShader(c.GL_FRAGMENT_SHADER, fragmentShaderSource);

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

pub fn createGraphicsPipeline() !void {
    //TODO: can I change it to use a stack allocator?
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    
    // loading the shader files (vert and fragment)
    const allocator = gp.allocator();
    var vertexShaderSource = try loadFromFileAsString(allocator, "./shaders/default.vert");
    var fragmentShaderSource = try loadFromFileAsString(allocator, "./shaders/default.frag");

    // actually create the shader program
    gGraphicsPipelineShaderProgram = try createShaderProgram(&vertexShaderSource, &fragmentShaderSource);
    
    // free your memory
    allocator.free(vertexShaderSource);
    allocator.free(fragmentShaderSource);
}

/// initialization of SDL
pub fn initializeProgram() !void {
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
pub fn preDraw() !void {
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

pub fn mainLoop() !void {
    while (!gQuit) {
        try input();

        try preDraw();

        try draw();

        c.SDL_GL_SwapWindow(gGraphicsApplicationWindow);
    }
}

pub fn cleanUp() !void {
    c.SDL_DestroyWindow(gGraphicsApplicationWindow);
    c.SDL_Quit();
}

pub fn main() !void {
    // sets up the graphics program
    try initializeProgram();
    
    // setup geometry
    try vertexSpecification();

    //create the graphics pipeline (vertex and fragment shaders)
    try createGraphicsPipeline();

    // application main loop
    try mainLoop();

    // clean up afer program termination
    try cleanUp();
}

// function that takes a path and an allocator and returns a string
// here using allocator since I don't know how bigger the file will be.
pub fn loadFromFileAsString(allocator: std.mem.Allocator, stringPath: []const u8) ![]const u8 {
    var path_buffer: [std.fs.MAX_PATH_BYTES]u8 = undefined;
    const path: []u8 = std.fs.realpath(stringPath, &path_buffer) catch |e| {
        std.debug.print("IO-ERROR {s}", .{@errorName(e)});
        return e;
    };
    var file = try std.fs.cwd().openFile(path, .{ .mode= .read_only });
    defer file.close();
    var contents = try file.readToEndAlloc(allocator, std.math.maxInt(usize));
    return contents;
}

test "red file alloc" {
    var gp = std.heap.GeneralPurposeAllocator(.{ .safety = true }){};
    defer _ = gp.deinit();
    const allocator = gp.allocator();
    var pippo = try loadFromFileAsString(allocator, "./shaders/default.vert");
    print("pippo:\n{s}", .{pippo});
    allocator.free(pippo);
}
