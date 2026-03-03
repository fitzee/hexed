#import <Cocoa/Cocoa.h>

void mac_show_about(const char *name, const char *version, const char *copyright) {
    NSDictionary *opts = @{
        @"ApplicationName": [NSString stringWithUTF8String:name],
        @"ApplicationVersion": [NSString stringWithUTF8String:version],
        @"Copyright": [NSString stringWithUTF8String:copyright]
    };
    [NSApp orderFrontStandardAboutPanelWithOptions:opts];
}
