//
//  SafeUINavigationController.m
//  MotionDemo
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
@end

//////////////////////////////////////////////////////////////////

@interface SafeUINavigationController ()
@property () NSOperationQueue *q;
@property () NSMutableArray *finishOps;
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
	if ([self respondsToSelector:@selector(interactivePopGestureRecognizer)])
		self.interactivePopGestureRecognizer.enabled = NO;
}

// This delegate function tells us when a push or pop has completed.
- (void)navigationController:(UINavigationController *)navigationController didShowViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	// The operation that finished was the first one queued since they're serialized.
	Op *op = self.finishOps.firstObject;
	[self finishedOp:op];
}

//////////////////////////////////////////////////////////////
// Helpers

- (void)finishedOp:(Op *)op
{
	DebugLog(@"Finished a %@ transition.", (op.type == OP_PUSH ? @"PUSH" : @"POP"));
	[self.finishOps removeObject:op];
	// Disconnect the operations so both can be freed
	op.pairedOp.pairedOp = nil;
	op.pairedOp = nil;
	// Mark the operation as finished. We could probably call [op start] instead.
	[self.q addOperation:op];
	// The next operation will start if there is one.
}

- (void)doPush:(Op *)pushOp
{
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
		DebugLog(@"Scheduling Push.");
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
	popOp.pairedOp = popFinished;
	popFinished.pairedOp = popOp;
	[popFinished addDependency:popOp];
	[self.finishOps addObject:popFinished];
	// Schedule it
	DebugLog(@"Scheduling Pop: %@", popOp.vc);
	[self.q addOperation:popOp];
}


////////////////////////////////////////////////////////////////////////////
// We must override any method which pushes or pops a view from the navigation stack.
- (void)pushViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:viewController modal:NO];
	[pushOp addExecutionBlock:^{
		DebugLog(@"Pushing viewController: %@", viewController);
		[super pushViewController:viewController animated:animated];
	}];
	[self doPush:pushOp];
}

- (UIViewController *)popViewControllerAnimated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
	[popOp addExecutionBlock:^{
		DebugLog(@"Popping viewController: %@", self.topViewController);
		[super popViewControllerAnimated:animated];
	}];
	[self doPop:popOp];
    return nil;
}

- (NSArray *)popToRootViewControllerAnimated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
	[popOp addExecutionBlock:^{
		DebugLog(@"Popping to root view controller.");
		[super popToRootViewControllerAnimated:animated];
	}];
	[self doPop:popOp];
	return nil;
}

- (NSArray *)popToViewController:(UIViewController *)viewController animated:(BOOL)animated
{
	Op *popOp = [[Op alloc] initWithType:OP_POP viewController:self.topViewController modal:NO];
	[popOp addExecutionBlock:^{
		DebugLog(@"Popping to viewController: %@", viewController);
		[super popToViewController:viewController animated:animated];
	}];
	[self doPop:popOp];
	return nil;
}

- (void)presentViewController:(UIViewController *)viewControllerToPresent animated:(BOOL)flag completion:(void (^)(void))completion
{
	Op *pushOp = [[Op alloc] initWithType:OP_PUSH viewController:viewControllerToPresent modal:YES];
	// Use weak reference inside the block as not to create a retain cycle. This does mean we must retain the pushOp until completion. This is done by the pariedOp member.
	__weak Op *weakPushOp = pushOp;
	[pushOp addExecutionBlock:^{
		DebugLog(@"Presenting viewController: %@", viewControllerToPresent);
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
	// Use weak reference inside the block as not to create a retain cycle.  This does mean we must retain the popOp until completion. This is done by the pariedOp member.
	__weak Op *weakPopOp = popOp;
	[popOp addExecutionBlock:^{
		UIViewController *vc = self.presentedViewController;
		DebugLog(@"Dismissing viewController: %@", vc);
		[super dismissViewControllerAnimated:flag completion:
		 ^{
			 if (completion)
				 completion();
			 [self finishedOp:weakPopOp.pairedOp];
		 }];
	}];
	[self doPop:popOp];
}
@end
