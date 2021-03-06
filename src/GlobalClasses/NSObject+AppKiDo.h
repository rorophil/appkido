//
//  NSObject+AppKiDo.h
//  AppKiDo
//
//  Created by Andy Lee on 3/10/13.
//  Copyright (c) 2013 Andy Lee. All rights reserved.
//

#import <Foundation/Foundation.h>

@interface NSObject (AppKiDo)

/*! Of the form <NSTableView: 0x179a770>, and nothing else. */
- (NSString *)ak_bareDescription;

/*!
 * Logs a sequence of objects starting at self and ending when we either hit
 * nil or detect a loop. Sends nextObjectSelector to each object to get the next
 * object in the sequence.
 */
- (void)ak_printSequenceUsingSelector:(SEL)nextObjectSelector;  // [agl] a block version might be nice

@end
