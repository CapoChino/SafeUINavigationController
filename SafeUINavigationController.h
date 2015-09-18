//
//  SafeUINavigationController.h
//
//  Created by Casey Persson on 6/12/14.
//

#import <UIKit/UIKit.h>

//#define SAFE_NAV_DEBUG
//#define INTERCEPT_TOUCHES

#ifdef SAFE_NAV_DEBUG
#define DebugLog(fmt,...) NSLog(@"%@",[NSString stringWithFormat:(fmt), ##__VA_ARGS__]);
#else
// If debug mode hasn't been enabled, don't do anything when the macro is called
#define DebugLog(...)
#endif

/* The purpose of this subclass is to serialize multiple subsequent pushes/pops of the navigation stack, waiting for animations and viewWill/Did.. calls to happen as appropriate.  Without this class, you can get unbalanced call warnings by calling:

	[navigationController pushViewController:myBottomVC animated:NO];
    [navigationController pushViewController:myTopVC animated:YES];
 
	With this class, the above calls would be serialized properly.
 
   Caveats:
   * This class sets it's own delegate member, which is required for correct operation.  Thus users may not set the delegate of this class.  (The class could be augmented to accomodate this if necessary.)
   * The pop functions here return before the actual pop happens, thus they cannot return the popped VCs so return nil.
*/
@interface SafeUINavigationController : UINavigationController <UINavigationControllerDelegate, UIGestureRecognizerDelegate>
@end
