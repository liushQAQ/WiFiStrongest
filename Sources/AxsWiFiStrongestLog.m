#import "AxsWiFiStrongestLog.h"
#import "AxsWiFiStrongestConfig.h"
#import <pthread.h>

static NSString * const AxsWiFiStrongestLogDirectory = @"/var/mobile/Library/Logs";
static NSString * const AxsWiFiStrongestLogFile = @"/var/mobile/Library/Logs/AxsWiFiStrongest.log";
static const unsigned long long AxsWiFiStrongestLogMaxBytes = 256 * 1024;
static const NSInteger AxsWiFiStrongestLogKeepLines = 400;

@implementation AxsWiFiStrongestLog

+ (NSString *)axs_wifistrongest_path {
    return AxsWiFiStrongestLogFile;
}

+ (void)axs_wifistrongest_append:(NSString *)line {
    static pthread_mutex_t lock = PTHREAD_MUTEX_INITIALIZER;
    pthread_mutex_lock(&lock);
    @autoreleasepool {
        NSFileManager *manager = [NSFileManager defaultManager];
        if (![manager fileExistsAtPath:AxsWiFiStrongestLogDirectory]) {
            [manager createDirectoryAtPath:AxsWiFiStrongestLogDirectory
               withIntermediateDirectories:YES attributes:nil error:NULL];
        }
        NSDictionary *attributes = [manager attributesOfItemAtPath:AxsWiFiStrongestLogFile error:NULL];
        if ([attributes fileSize] > AxsWiFiStrongestLogMaxBytes) {
            NSString *existing = [NSString stringWithContentsOfFile:AxsWiFiStrongestLogFile
                                    encoding:NSUTF8StringEncoding error:NULL] ?: @"";
            NSArray<NSString *> *lines = [existing componentsSeparatedByString:@"\n"];
            NSUInteger start = lines.count > (NSUInteger)AxsWiFiStrongestLogKeepLines
                ? lines.count - (NSUInteger)AxsWiFiStrongestLogKeepLines : 0;
            NSString *trimmed = [[lines subarrayWithRange:NSMakeRange(start, lines.count - start)]
                                 componentsJoinedByString:@"\n"];
            [trimmed writeToFile:AxsWiFiStrongestLogFile atomically:YES
                        encoding:NSUTF8StringEncoding error:NULL];
        }
        NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
        if (![manager fileExistsAtPath:AxsWiFiStrongestLogFile]) {
            [data writeToFile:AxsWiFiStrongestLogFile atomically:YES];
        } else {
            NSFileHandle *handle = [NSFileHandle fileHandleForWritingAtPath:AxsWiFiStrongestLogFile];
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

+ (NSString *)axs_wifistrongest_stamp {
    static NSDateFormatter *formatter;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        formatter = [[NSDateFormatter alloc] init];
        formatter.dateFormat = @"MM-dd HH:mm:ss";
    });
    return [formatter stringFromDate:[NSDate date]];
}

+ (void)axs_wifistrongest_log:(NSString *)format, ... {
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self axs_wifistrongest_append:[NSString stringWithFormat:@"%@ %@\n",
                                    [self axs_wifistrongest_stamp], body]];
}

+ (void)axs_wifistrongest_verbose:(NSString *)format, ... {
    if (![[AxsWiFiStrongestConfig axs_wifistrongest_shared] axs_wifistrongest_debugLog]) {
        return;
    }
    va_list args;
    va_start(args, format);
    NSString *body = [[NSString alloc] initWithFormat:format arguments:args];
    va_end(args);
    [self axs_wifistrongest_append:[NSString stringWithFormat:@"%@ · %@\n",
                                    [self axs_wifistrongest_stamp], body]];
}

+ (NSString *)axs_wifistrongest_tailWithLines:(NSInteger)lines {
    NSString *content = [NSString stringWithContentsOfFile:AxsWiFiStrongestLogFile
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

+ (void)axs_wifistrongest_clear {
    [[NSFileManager defaultManager] removeItemAtPath:AxsWiFiStrongestLogFile error:NULL];
}

@end
