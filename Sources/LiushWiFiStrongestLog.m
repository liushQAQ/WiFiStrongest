#import "LiushWiFiStrongestLog.h"
#import "LiushWiFiStrongestConfig.h"
#import <pthread.h>

static NSString * const LiushWiFiStrongestLogDirectory = @"/var/mobile/Library/Logs";
static NSString * const LiushWiFiStrongestLogFile = @"/var/mobile/Library/Logs/LiushWiFiStrongest.log";
static const unsigned long long LiushWiFiStrongestLogMaxBytes = 256 * 1024;
static const NSInteger LiushWiFiStrongestLogKeepLines = 400;

@implementation LiushWiFiStrongestLog

+ (NSString *)liush_wifistrongest_path {
    return LiushWiFiStrongestLogFile;
}

+ (void)liush_wifistrongest_append:(NSString *)line {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    @autoreleasepool {
        NSFileManager *manager = [NSFileManager defaultManager];
        if (![manager fileExistsAtPath:LiushWiFiStrongestLogDirectory]) {
            [manager createDirectoryAtPath:LiushWiFiStrongestLogDirectory
               withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        NSDictionary *attributes = [manager attributesOfItemAtPath:LiushWiFiStrongestLogFile error:NULL];
        if ([attributes fileSize] > LiushWiFiStrongestLogMaxBytes) {
            NSString *existing = [NSString stringWithContentsOfFile:LiushWiFiStrongestLogFile
                                    encoding:NSUTF8StringEncoding error:NULL] ?: @"";
            NSArray<NSString *> *lines = [existing componentsSeparatedByString:@"\n"];
            NSUInteger start = lines.count > (NSUInteger)LiushWiFiStrongestLogKeepLines
                ? lines.count - (NSUInteger)LiushWiFiStrongestLogKeepLines : 0;
            NSString *trimmed = [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)]
                                 componentsJoinedByString:@"\n"];
            [trimmed writeToFile:LiushWiFiStrongestLogFile atomically:YES
                        encoding:NSUTF8StringEncoding error:NULL];
        }
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![manager fileExistsAtPath:LiushWiFiStrongestLogFile]) {
            [data writeToFile:LiushWiFiStrongestLogFile atomically:YES];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:LiushWiFiStrongestLogFile];
            @try {
                [handle seekToEndOfFile];
                [handle writeData:data];
            } @catch (__unused NSException *exception) {
            } @finally {
                [handle closeFile];
            }
        }
    }
    pthread_mutex_unlock(&lock);
}

+ (NSString *)liush_wifistrongest_stamp {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate date]];
}

+ (void)liush_wifistrongest_log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self liush_wifistrongest_append:[NSString stringWithFormat:@"%@ %@\n",
                                    [self liush_wifistrongest_stamp], body]];
}

+ (void)liush_wifistrongest_verbose:(NSString *)format, ... {
    if (![[LiushWiFiStrongestConfig liush_wifistrongest_shared] liush_wifistrongest_debugLog]) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self liush_wifistrongest_append:[NSString stringWithFormat:@"%@ · %@\n",
                                    [self liush_wifistrongest_stamp], body]];
}

+ (NSString *)liush_wifistrongest_tailWithLines:(NSInteger)lines {
    NSString *content = [NSString stringWithContentsOfFile:LiushWiFiStrongestLogFile
                            encoding:NSUTF8StringEncoding error:NULL];
    if (content.length == 0) {
        return @"";
    }
    NSArray<NSString *> *all = [content componentsSeparatedByString:@"\n"];
    NSInteger count = (NSInteger)all.count;
    NSInteger start = lines > 0 && count > lines ? count - lines : 0;
    return [[all subarrayWithRange:NSMakeRange((NSUInteger)start, (NSUInteger)(count - start))]
            componentsJoinedByString:@"\n"];
}

+ (void)liush_wifistrongest_clear {
    [[NSFileManager defaultManager] removeItemAtPath:LiushWiFiStrongestLogFile error:NULL];
}

@end
