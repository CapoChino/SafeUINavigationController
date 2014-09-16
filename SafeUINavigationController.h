//
//  SafeUINavigationController.h
//  MotionDemo
//
//  Created by Casey Persson on 6/12/14.
//
//

#import <UIKit/UIKit.h>

/* The purpose of this subclass is to serialize multiple subsequent pushes/pops of the navigation stack, waiting for animations and viewWill/Did.. calls to happen as appropriate.  Without this class, you can get unbalanced call warnings by calling:

	[navigationController pushViewController:myBottomVC animated:NO];
    [navigationController pushViewController:myTopVC animated:YES];
 
	With this class, the above calls would be serialized properly.
 
   Caveats:
   * This class sets it's own delegate member, which is required for correct operation.  Thus users may not set the delegate of this class.  (The class could be augmented to accomodate this if necessary.)
   * The pop functions here return before the actual pop happens, thus they cannot return the popped VCs so return nil.
*/
@interface SafeUINavigationController : UINavigationController <UINavigationControllerDelegate>
@end
