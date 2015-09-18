//
//  SafeUINavigationController.m
//
//  Created by Casey Persson on 6/12/14.
//
//

#import "SafeUINavigationController.h"

//////////////////////////////////////////////////////////////////
// Represents an animation operation
typedef enum {
	OP_PUSH,
	OP_POP,
} OP_TYPE;

@interface Op : NSBlockOperation
@property () OP_TYPE type;
@property () BOOL modal;
@property () UIViewController *vc;
// A ViewController transition is comprised of 2 "Op"s, the operation that starts the transition, and the operation that represents the end of the transition.  Each side of the transition has a pointer to the other end via "pairedOp".
@property () Op *pairedOp;
- (id)initWithType:(OP_TYPE)type viewController:(UIViewController *)viewController modal:(BOOL)modal;
@end

@implementation Op
- (id)initWithType:(OP_TYPE)type viewController:(UIViewController *)viewController modal:(BOOL)modal
{
	self = [super init];
	if (self)
	{
		self.type = type;
		self.vc = viewController;
		self.modal = modal;
	}
	return self;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"%@ %@ view controller %@%@",
            self.name,
            self.type == OP_PUSH ? @"Pushing" : @"Popping",
            self.vc,
            self.modal ? @" modally" : @""
            ];
}
@end

//////////////////////////////////////////////////////////////////

@interface SafeUINavigationController ()
@property () NSOperationQueue *q;
@property () NSMutableArray *finishOps;
@property () UIWindow *touchInterceptor;
@property () UIWindow *oldKeyWindow;
@end

@implementation SafeUINavigationController

- (void)setup
{
    self.q = [NSOperationQueue mainQueue];
    self.finishOps = [[NSMutableArray alloc] init];
    self.delegate = self;
}

- (id)initWithNibName:(NSString *)nibNameOrNil bundle:(NSBundle *)nibBundleOrNil
{
    self = [super initWithNibName:nibNameOrNil bundle:nibBundleOrNil];
    if (self) {
        [self setup];
    }
    return self;
}

- (id)initWithCoder:(NSCoder *)aDecoder
{
    self = [super initWithCoder:aDecoder];
    if (self)
    {
        [self setup];
    }
    return self;
}

- (NSString *)description {
    NSDictionary *descriptionDictionary =
    [NSDictionary dictionaryWithObjectsAndKeys:
        super.description, @"self",
        self.q, @"Queue",
        self.q.operations, @"Queue Operations",
        self.finishOps, @"Finish Ops:",
        nil];
    return [descriptionDictionary description];
}

- (void)setDelegate:(id<UINavigationControllerDelegate>)delegate
{
	// This class needs delegate updates, so setting an outside delegate is illegal.  This could be fixed, of course, but no sense doing it til we need it.
    assert(delegate == self);
    [super setDelegate:delegate];
}

- (void)didReceiveMemoryWarning
{
    [super didReceiveMemoryWarning];
    // Dispose of any resources that can be recreated.
}

- (void)viewDidLoad
{
    [super viewDidLoad];
	// Disable the swipe-to-go-back feature that was introduced in iOS7, as it can fairly easily happen accidentally.  When it does, even if you don't swipe it all the way but instead come back to the graph, the uiscrollview's zoom is reset, which is quite annoying. Worse, our didShowViewController delegate function if the user aborts the pop swipe, thus leaving our queue stuck forever waiting for the finish. Disabling this fixes issue #81.
    if ([self respondsToSelector:@selector(interactivePopGestureRecognizer)]) {
		self.interactivePopGestureRecognizer.enabled = NO;
        self.interactivePopGestureRecognizer.delegate = self;
    }
#if defined(INTERCEPT_TOUCHES)
    self.touchInterceptor = [[UIWindow alloc] init];
#if defined(SAFE_NAV_DEBUG)
    self.touchInterceptor.backgroundColor = [UIColor yellowColor];
    self.touchInterceptor.alpha = 0.3;
#endif
#endif
}

- (void)disableTaps
{
#if defined(INTERCEPT_TOUCHES)
    DebugLog(@"Disabling taps");
//    if (self.oldKeyWindow == nil)
    {
        self.oldKeyWindow = [[UIApplication sharedApplication] keyWindow];
    }
//    else
//    {
//        NSLog(@"Warning: disableTaps called while taps already disabled. This may indicate a serialization problem in SafeUINavigationController");
//    }
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0f)
        self.touchInterceptor.frame = [UIScreen mainScreen].nativeBounds;
    else
        self.touchInterceptor.frame = [UIScreen mainScreen].bounds;
    self.touchInterceptor.windowLevel = UIWindowLevelAlert;
    [self.touchInterceptor makeKeyAndVisible];
#endif
}

- (void)enableTaps
{
#if defined(INTERCEPT_TOUCHES)
    DebugLog(@"Enabling taps");
    self.touchInterceptor.hidden = YES;
    [self.oldKeyWindow makeKeyAndVisible];
    self.oldKeyWindow = nil;
#endif
}

// This delegate function tells us when a push or pop has completed.
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
    // The operation that finished should the self.finishOps since they're serialized.  However, sometimes this delegate method gets called twice at startup.  So we're a little stricter.
    for (Op *op in self.finishOps) {
        // Maks sure that if it's a push, that the view controller being displayed matches what the operation says.  This will weed out a duplicate call to this delegate function.
        if (op.type == OP_PUSH && op.vc == viewController) {
            // Push operation finished
            [self finishedOp:op];
            break;
        } else if (op.type == OP_POP) {
            // For POP, the viewcontroller being shown is the one UNDER the operation's VC, so we can't compare them.
            [self finishedOp:op];
            break;
        }
    }
}

// InteractivePopGesture is turned off for safe nav
- (BOOL)gestureRecognizerShouldBegin:(UIGestureRecognizer *)gestureRecognizer
{
    return NO;
}

//////////////////////////////////////////////////////////////
// Helpers

- (void)finishedOp:(Op *)op
{
    DebugLog(@"%@", op.description);
	[self.finishOps removeObject:op];
	// Disconnect the operations so both can be freed
	op.pairedOp.pairedOp = nil;
	op.pairedOp = nil;
	// Mark the operation as finished. We could probably call [op start] instead.
	[self.q addOperation:op];
	// The next operation will start if there is one.
    [self enableTaps];
}

- (void)doPush:(Op *)pushOp
{
    if ([self.viewControllers containsObject:pushOp.vc]) {
        DebugLog(@"Ignoring operation because the view controller is already on the stack: %@", pushOp);
        return;
    }
    BOOL immediate;
	if (self.finishOps.count == 0)
	{
		immediate = YES;
	}
	else
	{
		immediate = NO;
		// Can't do the push until the last operation finishes
		[pushOp addDependency:self.finishOps.lastObject];
	}
	Op *pushFinished = [[Op alloc] initWithType:OP_PUSH viewController:pushOp.vc modal:pushOp.modal];
    pushFinished.name = @"Finish:";
	pushOp.pairedOp = pushFinished;
	pushFinished.pairedOp = pushOp;
	[self.finishOps addObject:pushFinished];
	if (immediate)
	{
		DebugLog(@"Pushing immediately.");
		[pushOp start];
	}
	else
	{
		DebugLog(@"Scheduling: %@", pushOp);
		[pushFinished addDependency:pushOp];
		// Schedule it
        [self.q addOperation:pushOp];
	}
}

- (void)doPop:(Op *)popOp
{
	// Can't do the pop until the last operation finishes
	if (popOp.modal)
	{
		for (NSInteger i=self.finishOps.count-1; i>=0; i--)
		{
			if (((Op *)self.finishOps[i]).modal)
			{
				[popOp addDependency:self.finishOps[i]];
				break;
			}
		}
	}
	else
	{
		if (self.finishOps.lastObject)
		{
			[popOp addDependency:self.finishOps.lastObject];
		}
	}
	Op *popFinished = [[Op alloc] initWithType:OP_POP viewController:popOp.vc modal:popOp.modal];
    popFinished.name = @"Finish:";
	popOp.pairedOp = popFinished;
	popFinished.pairedOp = popOp;
	[popFinished addDependency:popOp];
	[self.finishOps addObject:popFinished];
	// Schedule it
	DebugLog(@"Scheduling: %@", popOp);
	[self.q addOperation:popOp];
}


////////////////////////////////////////////////////////////////////////////
// We must override any method which pushes or pops a view from the navigation stack.
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:viewController modal:NO];
    pushOp.name = @"Start:";
    __unused __weak Op *weakOp = pushOp;
	[pushOp addExecutionBlock:^{
        DebugLog(@"%@", weakOp.description);
        [self disableTaps];
		[super pushViewController:viewController animated:animated];
	}];
	[self doPush:pushOp];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
    popOp.name = @"Start:";
    __unused __weak Op *weakOp = popOp;
	[popOp addExecutionBlock:^{
        DebugLog(@"%@", weakOp.description);
        [self disableTaps];
		[super popViewControllerAnimated:animated];
	}];
	[self doPop:popOp];
    return nil;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
    popOp.name = @"Start:";
	[popOp addExecutionBlock:^{
		DebugLog(@"Popping to root view controller.");
        [self disableTaps];
		[super popToRootViewControllerAnimated:animated];
	}];
	[self doPop:popOp];
	return nil;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
    popOp.name = @"Start:";
    __unused __weak Op *weakOp = popOp;
	[popOp addExecutionBlock:^{
        DebugLog(@"%@", weakOp.description);
        [self disableTaps];
		[super popToViewController:viewController animated:animated];
	}];
	[self doPop:popOp];
	return nil;
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion
{
	Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:viewControllerToPresent modal:YES];
    pushOp.name = @"Start:";
	// Use weak reference inside the block as not to create a retain cycle. This does mean we must retain the pushOp until completion. This is done by the pariedOp member.
	__weak Op *weakPushOp = pushOp;
	[pushOp addExecutionBlock:^{
		DebugLog(@"%@", weakPushOp.description);
        [self disableTaps];
		[super presentViewController:viewControllerToPresent animated:flag completion:
		 ^{
			 if (completion)
				 completion();
			 [self finishedOp:weakPushOp.pairedOp];
		 }];
	}];
	[self doPush:pushOp];
}

- (void)dismissViewControllerAnimated:(BOOL)flag completion:(void (^)(void))completion
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.presentedViewController modal:YES];
    popOp.name = @"Start:";
	// Use weak reference inside the block as not to create a retain cycle.  This does mean we must retain the popOp until completion. This is done by the pariedOp member.
	__weak Op *weakPopOp = popOp;
	[popOp addExecutionBlock:^{
		DebugLog(@"Dismissing viewController: %@", self.presentedViewController);
        [self disableTaps];
		[super dismissViewControllerAnimated:flag completion:
		 ^{
			 if (completion)
				 completion();
			 [self finishedOp:weakPopOp.pairedOp];
		 }];
	}];
	[self doPop:popOp];
}
// I don't think we need to override these because it seems Apple has finally fixed the issue internally.  The override doesn't seem to work right, but if you call showViewController twice in a row without this override, it actually pushes one VC, then the next, just like pushing twice with SafeUINavigationController.
#if 0
- (void)showViewController:(UIViewController *)vc sender:(id)sender
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0f)
    {
        Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:vc modal:NO];
        [pushOp addExecutionBlock:^{
            DebugLog(@"Showing viewController: %@", vc);
            [self disableTaps];
            [super showViewController:vc sender:sender];
        }];
        [self doPush:pushOp];
    }
}

- (void)showDetailViewController:(UIViewController *)vc sender:(id)sender
{
    if ([[[UIDevice currentDevice] systemVersion] floatValue] >= 8.0f)
    {
        Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:vc modal:NO];
        [pushOp addExecutionBlock:^{
            DebugLog(@"Showing detail viewController: %@", vc);
            [self disableTaps];
            [super showDetailViewController:vc sender:sender];
        }];
        [self doPush:pushOp];
    }
}
#endif
@end
