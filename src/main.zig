const std = @import("std");
const gtk = @import("gtk");
const Application = gtk.Application;
const ApplicationWindow = gtk.ApplicationWindow;
const Box = gtk.Box;
const Button = gtk.Button;
const Image = gtk.Image;
const Widget = gtk.Widget;
const CheckButton = gtk.CheckButton;
const HeaderBar = gtk.HeaderBar;
const Window = gtk.Window;
const CenterBox = gtk.CenterBox;
const gio = gtk.gio;
const GApplication = gio.Application;

const requester = @import("requester.zig");

var current_image_count: usize = 0;
var gpa = std.heap.GeneralPurposeAllocator(.{}){};
const allocator = gpa.allocator();
var list = std.ArrayList([35]u8).init(allocator);

/// This is run in a separate thread
/// which is supposed to clean itself up.
fn prefetch() void {
    defer list.deinit();
    const prefetch_log = std.log.scoped(.Prefetch);

    while (true) {
        if (list.items.len <= current_image_count + 2) {
            const catgirl_image_path = requester.loadImage(allocator) catch {
                // most likely ratelimit
                prefetch_log.err("failed to get catgirl image (life sucks)\t:(", .{});
                std.time.sleep(3000 * std.time.ms_per_s);
                continue;
            };
            defer allocator.free(catgirl_image_path);

            var buf: [35]u8 = undefined;
            @memcpy(&buf, catgirl_image_path[0..35]);
            list.append(buf) catch {
                // append fails if the process runs OOM
                prefetch_log.err("Out of memory when trying to expand list...\n", .{});
                std.process.exit(1);
            };
            prefetch_log.info("added {s} to cache || cache image count: {d}", .{ buf, list.items.len });
        }
        std.time.sleep(100 * std.time.ns_per_ms);
    }
}

const ButtonName = enum { previous, next };

const button_log = std.log.scoped(.Button);
pub fn buttonClicked(self: *Button, image: *Image, btnname: ButtonName) void {
    _ = self;

    // actually, this boils down to preference.
    current_image_count = switch (btnname) {
        .previous => if (current_image_count < list.items.len) current_image_count -| 1,
        .next => if (current_image_count + 1 < list.items.len) current_image_count + 1,
    };

    var buf: [35:0]u8 = undefined;
    const img = list.items[current_image_count];
    @memcpy(buf[0..35], img[0..35]);
    buf[35] = 0;

    image.setFromFile(&buf);
    // do you know what std.debug.print does? and why you should **only** use it to debug?
    // not sure if, but it also doesn't write to stdout
    button_log.info("set image to {s} || current image id: {}\n", .{ img, current_image_count });
}

fn createButton(label: *const [1:0]u8, image: *Image, btnname: ButtonName) *Button {
    var button = Button.newWithLabel(label);
    const button_widget = button.into(Widget);
    button_widget.setHexpandSet(true);
    _ = button.connectClicked(buttonClicked, .{ image, btnname }, .{});

    return button;
}

fn changeNsfw(self: *CheckButton) void {
    const is_active = self.getActive();
    requester.enable_nsfw = is_active;
}

fn buildUi(app: *GApplication) void {
    const ui = std.log.scoped(.Ui);
    const application = app.tryInto(Application) orelse return;
    var window = gtk.ApplicationWindow.new(application).into(Window);

    var vbox = Box.new(gtk.Orientation.vertical, 5);

    var nsfw_checkbox = CheckButton.newWithLabel("enable nsfw");
    _ = nsfw_checkbox.connectToggled(changeNsfw, .{}, .{});
    const nsfw_checkbox_widget = nsfw_checkbox.into(Widget);

    vbox.append(nsfw_checkbox_widget);

    const thread1 = std.Thread.spawn(.{}, prefetch, .{}) catch {
        ui.err("Creating prefetcher thread failed. Exiting...", .{});
        std.process.exit(1);
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

    const button_next = createButton(">", image, ButtonName.next).into(Widget);
    const button_previous = createButton("<", image, ButtonName.previous).into(Widget);

    centerbox.setStartWidget(button_previous);
    centerbox.setEndWidget(button_next);

    window.setChild(vbox.into(Widget));
    window.setDefaultSize(200, 500);

    const titlebar = HeaderBar.new();
    titlebar.setShowTitleButtons(false);
    const titlebar_widget = titlebar.into(Widget);

    const menubtn = gtk.MenuButton.new();
    const randompopover = gtk.Popover.new();
    const popoverbox = Box.new(.vertical, 0);

    popoverbox.append(nsfw_checkbox_widget);
    randompopover.setChild(popoverbox.into(Widget));

    menubtn.setPopover(randompopover.into(Widget));
    titlebar.packEnd(menubtn.into(Widget));

    window.setTitlebar(titlebar_widget);
    window.present();
}

pub fn main() !void {
    var app = Application.new("org.cargrilldownloader", .{}).into(GApplication);
    defer app.__call("unref", .{});
    _ = app.connectActivate(buildUi, .{}, .{});
    _ = app.run(std.os.argv);
}
