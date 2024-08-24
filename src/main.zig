const std = @import("std");
const gtk = @import("gtk");
const Application = gtk.Application;
const ApplicationWindow = gtk.ApplicationWindow;
const Box = gtk.Box;
const Button = gtk.Button;
const Image = gtk.Image;
const Widget = gtk.Widget;
const CheckButton = gtk.CheckButton;
const Window = gtk.Window;
const CenterBox = gtk.CenterBox;
const gio = gtk.gio;
const GApplication = gio.Application;

const requester = @import("requester.zig");

var current_image: usize = 0;
const allocator = std.heap.page_allocator;
var list = std.ArrayList([35]u8).init(allocator);

fn watch_images_thingy() void {
    var arena = std.heap.ArenaAllocator.init(std.heap.page_allocator);
    defer arena.deinit();
    const alloc = arena.allocator();

    while (true) {
        if (list.items.len <= current_image + 20) {
            const catgirl_image_path = requester.loadImage(alloc) catch {
                // most likely ratelimit
                std.log.err("failed to get catgirl image (life sucks)\t:(", .{});
                std.time.sleep(3000 * std.time.ms_per_s);
                continue;
            };

            var buf: [35]u8 = undefined;
            @memcpy(&buf, catgirl_image_path[0..35]);
            list.append(buf) catch {};
            std.log.info("added {s} to cache || cache image count: {d}", .{ buf, list.items.len });
        }
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

const ButtonName = enum { previous, next };

pub fn button_clicked(self: *Button, image: *Image, btnname: ButtonName) void {
    _ = self;
    if (btnname == .previous) {
        if (current_image < list.items.len and current_image != 0) current_image -= 1;
    } else {
        if (current_image + 1 < list.items.len) current_image += 1;
    }

    var buf: [35:0]u8 = undefined;
    const img = list.items[current_image];
    @memcpy(buf[0..35], img[0..35]);
    buf[35] = 0;

    image.setFromFile(&buf);
    std.debug.print("set image to {s} || current image id: {}\n", .{ img, current_image });
}

fn create_button(label: *const [1:0]u8, image: *Image, btnname: ButtonName) *Button {
    var button = Button.newWithLabel(label);
    const button_widget = button.into(Widget);
    button_widget.setHexpandSet(true);
    _ = button.connectClicked(button_clicked, .{ image, btnname }, .{});

    return button;
}

fn change_nsfw(self: *CheckButton) void {
    const is_active = self.getActive();
    requester.enable_nsfw = is_active;
}

fn buildUi(app: *GApplication) void {
    const application = app.tryInto(Application) orelse return;
    var window = gtk.ApplicationWindow.new(application).into(Window);

    var vbox = Box.new(gtk.Orientation.vertical, 5);

    var nsfw_checkbox = CheckButton.newWithLabel("enable nsfw");
    _ = nsfw_checkbox.connectToggled(change_nsfw, .{}, .{});
    const nsfw_checkbox_widget = nsfw_checkbox.into(Widget);

    vbox.append(nsfw_checkbox_widget);

    const thread1 = std.Thread.spawn(.{ .stack_size = 1024 * 1024 * 1024 * 5 }, watch_images_thingy, .{}) catch {
        std.debug.panic("a", .{});
    };
    thread1.detach();

    var centerbox = CenterBox.new();
    var centerbox_widget = centerbox.into(Widget);
    centerbox_widget.setHexpand(true);

    const image = Image.new();
    const image_widget = image.into(Widget);
    image_widget.setHexpandSet(true);
    image_widget.setVexpand(true);

    vbox.append(image_widget);
    vbox.append(centerbox_widget);

    const button_next = create_button(">", image, ButtonName.next).into(Widget);
    const button_previous = create_button("<", image, ButtonName.previous).into(Widget);

    centerbox.setStartWidget(button_previous);
    centerbox.setEndWidget(button_next);

    window.setChild(vbox.into(Widget));
    window.setDefaultSize(200, 500);
    window.present();
}

pub fn main() !void {
    var app = Application.new("org.cargrilldownloader", .{}).into(GApplication);
    defer app.__call("unref", .{});
    _ = app.connectActivate(buildUi, .{}, .{});
    _ = app.run(std.os.argv);
}
