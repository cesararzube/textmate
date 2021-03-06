#import "HTMLOutputWindow.h"
#import <OakAppKit/OakAppKit.h>
#import <OakFoundation/NSString Additions.h>
#import <command/runner.h>
#import <oak/debug.h>

OAK_DEBUG_VAR(HTMLOutputWindow);

@interface HTMLOutputWindowController ()
{
	OBJC_WATCH_LEAKS(HTMLOutputWindowController);
}
@property (nonatomic) HTMLOutputWindowController* retainedSelf;
@end

@implementation HTMLOutputWindowController
- (id)init
{
	if(self = [super init])
	{
		NSRect rect = [[NSScreen mainScreen] visibleFrame];
		rect = NSIntegralRect(NSInsetRect(rect, NSWidth(rect) / 3, NSHeight(rect) / 5));

		self.window         = [[NSWindow alloc] initWithContentRect:rect styleMask:(NSTitledWindowMask|NSClosableWindowMask|NSResizableWindowMask|NSMiniaturizableWindowMask) backing:NSBackingStoreBuffered defer:NO];
		self.htmlOutputView = [[OakHTMLOutputView alloc] init];

		[self.window bind:NSTitleBinding toObject:self.htmlOutputView.webView withKeyPath:@"mainFrameTitle" options:nil];
		[self.window bind:NSDocumentEditedBinding toObject:self.htmlOutputView withKeyPath:@"runningCommand" options:nil];
		[self.window setContentView:self.htmlOutputView];
		[self.window setDelegate:self];
		[self.window setReleasedWhenClosed:NO];
		[self.window setAutorecalculatesContentBorderThickness:NO forEdge:NSMinYEdge];
		[self.window setContentBorderThickness:25 forEdge:NSMinYEdge];
		[self.window setCollectionBehavior:NSWindowCollectionBehaviorMoveToActiveSpace|NSWindowCollectionBehaviorFullScreenAuxiliary];

		// Register to application activation/deactivation notification so we can tweak our collection behavior
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidActivate:) name:NSApplicationDidBecomeActiveNotification object:nil];
		[[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(applicationDidDeactivate:) name:NSApplicationDidResignActiveNotification object:nil];
	}
	return self;
}

- (void)applicationDidActivate:(NSNotification*)notification
{
	// Starting with 10.11 behavior must be changed after current event loop cycle <rdar://23587833>
	dispatch_async(dispatch_get_main_queue(), ^{
		self.window.collectionBehavior |= NSWindowCollectionBehaviorMoveToActiveSpace;
	});
}

- (void)applicationDidDeactivate:(NSNotification*)notification
{
	// Starting with 10.11 behavior must be changed after current event loop cycle <rdar://23587833>
	dispatch_async(dispatch_get_main_queue(), ^{
		self.window.collectionBehavior &= ~NSWindowCollectionBehaviorMoveToActiveSpace;
	});
}

+ (HTMLOutputWindowController*)HTMLOutputWindowWithRunner:(command::runner_ptr const&)aRunner
{
	D(DBF_HTMLOutputWindow, bug("%s\n", to_s(aRunner->uuid()).c_str()););
	HTMLOutputWindowController* res = [[self alloc] init];
	[res setCommandRunner:aRunner];
	return res;
}

- (void)showWindow:(id)sender
{
	self.retainedSelf = self;
	[self.window makeKeyAndOrderFront:nil];
}

- (void)close
{
	[self.window close];
}

- (void)setCommandRunner:(command::runner_ptr)aRunner
{
	_commandRunner = aRunner;

	self.window.title = [NSString stringWithCxxString:_commandRunner->name()];
	self.window.frameAutosaveName = [NSString stringWithFormat:@"HTML output for %@", [NSString stringWithCxxString:_commandRunner->uuid()]];
	[self.htmlOutputView loadRequest:URLRequestForCommandRunner(_commandRunner) environment:_commandRunner->environment() autoScrolls:_commandRunner->auto_scroll_output()];
	[self showWindow:self];
}

- (BOOL)running
{
	return self.htmlOutputView.isRunningCommand;
}

- (BOOL)needsNewWebView
{
	return _htmlOutputView.needsNewWebView;
}

- (BOOL)windowShouldClose:(id)sender
{
	D(DBF_HTMLOutputWindow, bug("\n"););
	if(!self.running)
		return YES;

	NSAlert* alert = [NSAlert alertWithMessageText:@"Stop task before closing?" defaultButton:@"Stop Task" alternateButton:@"Cancel" otherButton:nil informativeTextWithFormat:@"The job that the task is performing will not be completed."];
	OakShowAlertForWindow(alert, self.window, ^(NSInteger returnCode){
		D(DBF_HTMLOutputWindow, bug("close %s\n", BSTR(returnCode == NSAlertDefaultReturn)););
		if(returnCode == NSAlertDefaultReturn) /* "Stop" */
		{
			[self.window orderOut:self];
			[self.htmlOutputView stopLoading];
			[self.window close];
		}
	});
	return NO;
}

- (void)windowWillClose:(NSNotification*)notification
{
	[self performSelector:@selector(setRetainedSelf:) withObject:nil afterDelay:0];
}

- (void)dealloc
{
	D(DBF_HTMLOutputWindow, bug("\n"););
	[[NSNotificationCenter defaultCenter] removeObserver:self];
	self.window.delegate = nil;
}

- (IBAction)toggleHTMLOutput:(id)sender
{
	[self.window performClose:self];
}

- (BOOL)validateMenuItem:(NSMenuItem*)menuItem
{
	if([menuItem action] == @selector(toggleHTMLOutput:))
		[menuItem setTitle:@"Hide HTML Output"];
	return YES;
}
@end
