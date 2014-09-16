SafeUINavigationController
==========================

This Objective-C class is a drop-in replacement for UINavigationController, used in developing iOS apps.

When using Apple's standard UINavigationController, if code pushes or pops a view controller on a native UINavigationController before a previous push or pop animation is complete, your view controllers will get unbalanced calls to viewWillAppear, viewDidAppear, viewWillDisappear, and viewDidDissapear.  

The following snippet would cause problems:

    [navigationController pushViewController:myBottomVC animated:NO];
    [navigationController pushViewController:myTopVC animated:YES];

The navigation controller can sometimes wedge, rendering navigation buttons ineffective.

SafeUINavigationController fixes these problems by serializing pushes and pops.

Caveats
-------
* This class sets its own delegate member, which is required for correct operation.  Thus users may not set the delegate of this class.  (The class could be augmented to accomodate this if necessary.)
* The pop functions here return before the actual pop happens, thus they cannot return the popped VCs so return nil.
