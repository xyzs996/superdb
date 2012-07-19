//
//  JBShellView.m
//  TextViewShell
//
//  Created by Jason Brennan on 12-07-14.
//  Copyright (c) 2012 Jason Brennan. All rights reserved.
//

#import "JBShellView.h"


@interface JBShellView () <NSTextViewDelegate>
@property (nonatomic, assign) NSUInteger commandStart;
@property (nonatomic, assign) NSUInteger lastCommandStart;
@end

@implementation JBShellView


#pragma mark - Public API

- (id)initWithFrame:(CGRect)frame prompt:(NSString *)prompt inputHandler:(JBShellViewInputProcessingHandler)inputHandler
{
    self = [super initWithFrame:frame];
    if (self) {
        // Initialization code here.
		
		self.prompt = prompt;
		self.inputHandler = [inputHandler copy];
		
		[self setFont:[NSFont fontWithName:@"Menlo" size:18.0f]];
		[self setTextContainerInset:CGSizeMake(5.0f, 5.0f)];
		[self setDelegate:self];
		[self setAllowsUndo:YES];
		
		[self insertPrompt];
		
		self.commandStart = [[self string] length];
		

    }
    
    return self;
}


- (id)initWithFrame:(NSRect)frameRect {
	return [self initWithFrame:frameRect prompt:@"> " inputHandler:^(NSString *input, JBShellView *sender) {
		NSRange errorRange = [input rangeOfString:@"nwe"];
		if (errorRange.location != NSNotFound)
			[sender showErrorOutput:@"Did you mean: new" errorRange:errorRange];
		else {
			//[sender appendOutputWithNewlines:@"All good."];
			NSString *message = @"All good";
			NSMutableAttributedString *output = [[NSMutableAttributedString alloc] initWithString:message];
			NSDictionary *attributes = @{ NSBackgroundColorAttributeName : kJBShellViewSuccessColor, NSForegroundColorAttributeName : [NSColor whiteColor] };
			[message enumerateSubstringsInRange:NSMakeRange(0, [message length]) options:NSStringEnumerationByWords usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
				if ([substring isEqualToString:@"good"]) {
					[output addAttributes:attributes range:substringRange];
				}
			}];
			[sender appendAttributedOutput:output];
		}
	}];
}


+ (NSColor *)errorColor {
	return [NSColor colorWithCalibratedRed:1.000 green:0.314 blue:0.333 alpha:1.000];
}


+ (NSColor *)successColor {
	return [NSColor colorWithCalibratedRed:0.376 green:0.780 blue:0.000 alpha:1.000];
}

- (void)appendOutput:(NSString *)output {
	[self moveToEndOfDocument:self];
	[self insertText:output];
	self.commandStart = [[self string] length];
	[self scrollRangeToVisible:[self selectedRange]];
}


- (void)appendOutputWithNewlines:(NSString *)output {
	[self appendOutput:[output stringByAppendingFormat:@"\n"]];
}


- (void)showErrorOutput:(NSString *)output errorRange:(NSRange)errorRange {
	
	errorRange.location += self.lastCommandStart;
	
	
	// I don't understand this conditional.
	if (NSMaxRange(errorRange) >= [[self string] length] && errorRange.length > 1) {
		errorRange.length--;
	}
	
	if ([self shouldChangeTextInRange:errorRange replacementString:nil]) {
		NSTextStorage *textStorage = [self textStorage];
		[textStorage beginEditing];
		NSColor *errorColor = kJBShellViewSuccessColor;
		NSDictionary *attributes = @{ NSForegroundColorAttributeName : [NSColor whiteColor], NSBackgroundColorAttributeName : errorColor };
		[textStorage addAttributes:attributes range:errorRange];
		[textStorage endEditing];
		[self didChangeText];
	}
	
	
	[self appendOutputWithNewlines:[NSString stringWithFormat:@"\n%@", output]];
}


- (void)appendAttributedOutput:(NSAttributedString *)attributedOutput {
	[self moveToEndOfDocument:self];
	[[self textStorage] appendAttributedString:attributedOutput];
	self.commandStart = [[self string] length];
	[self scrollRangeToVisible:[self selectedRange]];
}


- (void)appendAttributedOutputWithNewLines:(NSAttributedString *)attributedOutput {
	
}

#pragma mark - NSTextView overrides

- (void)keyDown:(NSEvent *)theEvent {
	if ([theEvent type] != NSKeyDown) {
		[super keyDown:theEvent];
		return;
	}
	
	if (![[theEvent characters] length]) {
		// accent input, for example
		[super keyDown:theEvent];
		return;
	}
	
	unichar character = [[theEvent characters] characterAtIndex:0];
	NSUInteger modifierFlags = [theEvent modifierFlags];
	BOOL arrowKey = (character == NSLeftArrowFunctionKey
					 || character == NSRightArrowFunctionKey
					 || character == NSUpArrowFunctionKey
					 || character == NSDownArrowFunctionKey);
	
	// Is the insertion point greater than commandStart and also (not shift+arrow)?
	if ([self selectedRange].location < self.commandStart && !(modifierFlags & NSShiftKeyMask && (arrowKey))) {
		[self setSelectedRange:NSMakeRange(self.commandStart, 0)];
		[self scrollRangeToVisible:[self selectedRange]];
	}
	
	// When the control key is held down
	if (modifierFlags & NSControlKeyMask) {
		switch (character) {
			case NSCarriageReturnCharacter:
				[self insertNewlineIgnoringFieldEditor:self];
				break;
			case NSDeleteCharacter:
				[self setSelectedRange:NSMakeRange(self.commandStart, [[self string] length])];
				[self delete:self];
				break;
			case NSUpArrowFunctionKey:
				[self replaceCurrentCommandWith:nil];
				break;
			case NSDownArrowFunctionKey:
				[self replaceCurrentCommandWith:nil];
				break;
			default:
				[super keyDown:theEvent];
				break;
		}
	} else {
		switch (character) {
			case NSCarriageReturnCharacter:
				[self acceptInput];
				break;
			default:
				[super keyDown:theEvent];
				break;
		}
	}
}


#pragma mark - Movement

- (void)moveToBeginningOfLine:(id)sender {
	[self setSelectedRange:[self commandStartRange]];
}


- (void)moveToEndOfLine:(id)sender {
	[self moveToEndOfDocument:sender];
}


- (void)moveToBeginningOfParagraph:(id)sender {
	[self setSelectedRange:[self commandStartRange]];
}


- (void)moveToEndOfParagraph:(id)sender {
	[self moveToEndOfDocument:sender];
}


- (void)moveLeft:(id)sender {
	if ([self selectedRange].location > self.commandStart) {
		[super moveLeft:sender];
	}
}


- (void)moveUp:(id)sender {
	// If we are on the first line of the current command then replace current command with the previous one from history
	// else, apply the normal text editing behavior.
	
	NSUInteger oldLocation = [self selectedRange].location;
	[super moveUp:sender];
	
	if ([self selectedRange].location < self.commandStart || [self selectedRange].location == oldLocation) {
		// moved before the start of command entry OR not moved because we are on the first line of the text view
		
		NSUInteger promptBottomLocation = self.commandStart = [self.prompt length];
		NSUInteger promptEndLocation = self.commandStart;
		NSUInteger insertionLocation = [self selectedRange].location;
		
		if (insertionLocation >= promptBottomLocation && insertionLocation < promptEndLocation) {
			// Insertion point is on the prompt, so move to the start of the current command.
			[self setSelectedRange:[self commandStartRange]];
		} else {
			[self saveEditedCommand:self];
			[self replaceCurrentCommandWith:nil];
		}
	}
}


- (void)moveDown:(id)sender {
	// If we are on the last line of the current command then replace current command with the next history item
	// else, apply the normal text editing behavior.
	NSUInteger oldLocation = [self selectedRange].location;
	[super moveDown:sender];
	
	if ([self selectedRange].location == oldLocation || [self selectedRange].location == [[self string] length]) {
		// no movement OR move to end of the document because we are on the last line
		[self saveEditedCommand:self];
		[self replaceCurrentCommandWith:nil];
	}
}


#pragma mark - NSTextViewDelegate implementation

- (BOOL)textView:(NSTextView *)textView shouldChangeTextInRange:(NSRange)affectedCharRange replacementString:(NSString *)replacementString {
	// Do not accept a modification outside the current command start
	if (replacementString && affectedCharRange.location < self.commandStart) {
		NSBeep();
		return NO;
	} else {
		return YES;
	}
}


#pragma mark - Private API

- (NSRange)commandStartRange {
	return NSMakeRange(_commandStart, 0);
}


- (void)saveEditedCommand:sender {
	NSLog(@"saving edited command");
}

- (void)replaceCurrentCommandWith:string {
	NSLog(@"Replacing command!");
}


- (void)acceptInput {
	NSLog(@"Accepting input!");
	NSString *input = [[self string] substringFromIndex:self.commandStart];
	
	self.lastCommandStart = self.commandStart;
	// Check to see if the command has a length and that it was NOT the last item in the history, and add it
	if ([input length] > 0 /*&& ![input isEqualToString:[history mostRecentlyInsertedCommand]] */) {
		//[history addCommand:input];
	}
	
	//[history goToLast];
	[self moveToEndOfDocument:self];
	[self insertNewlineIgnoringFieldEditor:self];
//	NSString *output = @"";
//	if (nil != self.inputHandler) {
//		output = self.inputHandler(input);
//	}
//	[self insertText:output];
	if (nil != self.inputHandler) {
		self.inputHandler(input, self);
	}
	[self insertNewlineIgnoringFieldEditor:self];
	[self insertPrompt];
	[self scrollRangeToVisible:[self selectedRange]];
	self.commandStart = [[self string] length];
	[[self undoManager] removeAllActions];
	
}


- (void)insertPrompt {
	[super insertText:self.prompt];
}

@end
