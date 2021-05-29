/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The extension of CircleTextViewController that handles glyph substitution.
*/

import UIKit

extension CircleTextViewController {

    func triggerGlyphSubstitutionIfNeeded() {
        // Return if the text container doesn't have any text or if there isn't text overflow.
        // Content is an NSString because Swift string index uses Extended Grapheme Clusters,
        // which is different from the character index TextKit returns.
        //
        let layoutManager = textView.layoutManager
        let glyphRange = layoutManager.glyphRange(for: textView.textContainer)
        guard glyphRange.length > 1 else { return }

        let content = textView.textStorage.string as NSString
        let charRange = layoutManager.characterRange(forGlyphRange: glyphRange, actualGlyphRange: nil)
        guard charRange.location + charRange.length < content.length else { return }

        // Calculate the character range of the ending words. The result can be more than one word
        // to make sure the string to replace with an ellipsis is wide enough.
        // endingWordsCharRange.length < 3: ellipsis has three dots (...).
        //
        var endingWordsCharRange = NSRange(location: 0, length: 0)
        content.enumerateSubstrings(in: charRange, options: [.byWords, .reverse]) {
            (substring, substringRange, enclosingRange, stop) in
            if endingWordsCharRange.location > substringRange.location { // Merge the two ranges
                endingWordsCharRange.length += endingWordsCharRange.location - substringRange.location
                endingWordsCharRange.location = substringRange.location
            } else {
                endingWordsCharRange = substringRange
            }
            stop.pointee = endingWordsCharRange.length < 3 ? false : true
        }
        guard endingWordsCharRange.length >= 3 else { return }
        
        // Calculate flexibleSpaceGlyphRange and ellipsisGlyphRange.
        // This sample replaces the glyphs in ellipsisGlyphRange with an ellipsis,
        // and replaces the glyphs in flexibleSpaceGlyphRange with a flexible space.
        //
        let ellipsisCharRange = endingWordsCharRange
        ellipsisGlyphRange = layoutManager.glyphRange(forCharacterRange: ellipsisCharRange,
                                                      actualCharacterRange: nil)
        let flexibleSpaceCharIndex = endingWordsCharRange.location + endingWordsCharRange.length
        let flexibleSpaceCharRange = NSRange(location: flexibleSpaceCharIndex, length: 1)
        flexibleSpaceGlyphRange = layoutManager.glyphRange(forCharacterRange: flexibleSpaceCharRange,
                                                           actualCharacterRange: nil)
        
        layoutManager.invalidateGlyphs(forCharacterRange: endingWordsCharRange, changeInLength: 0,
                                       actualCharacterRange: nil)
        layoutManager.invalidateLayout(forCharacterRange: endingWordsCharRange,
                                       actualCharacterRange: nil)
    }
        
    func restoreSubstitutedGlyphsIfNeeded() {
        // Return if no substituation occurs.
        //
        guard let ellipsisGlyphRange = self.ellipsisGlyphRange,
            let flexibleSpaceGlyphRange = self.flexibleSpaceGlyphRange else { return }
        
        let endingWordsGlyphRange = NSUnionRange(ellipsisGlyphRange, flexibleSpaceGlyphRange)
        let layoutManager = textView.layoutManager
        let endingWordsCharRange = layoutManager.characterRange(forGlyphRange: endingWordsGlyphRange,
                                                                actualGlyphRange: nil)
        // Restore the glyphs that this sample replaced.
        // Clear ellipsisGlyphRange and flexibleSpaceGlyphRange so that glyph substitution doesn't occur.
        //
        self.ellipsisGlyphRange = nil
        self.flexibleSpaceGlyphRange = nil
        layoutManager.invalidateGlyphs(forCharacterRange: endingWordsCharRange, changeInLength: 0,
                                       actualCharacterRange: nil)
    }
}
extension CircleTextViewController: NSLayoutManagerDelegate {
    
    public func layoutManager(_ layoutManager: NSLayoutManager,
                              shouldGenerateGlyphs glyphs: UnsafePointer<CGGlyph>,
                              properties props: UnsafePointer<NSLayoutManager.GlyphProperty>,
                              characterIndexes charIndexes: UnsafePointer<Int>,
                              font aFont: UIFont,
                              forGlyphRange glyphRange: NSRange) -> Int {
        var ellipsisIntersection = NSRange(location: 0, length: 0)
        if let ellipsisGlyphRange = self.ellipsisGlyphRange {
            ellipsisIntersection = NSIntersectionRange(glyphRange, ellipsisGlyphRange)
        }
        var flexibleSpaceIntersection = NSRange(location: 0, length: 0)
        if let flexibleSpaceGlyphRange = self.flexibleSpaceGlyphRange {
            flexibleSpaceIntersection = NSIntersectionRange(glyphRange, flexibleSpaceGlyphRange)
        }
        
        guard ellipsisIntersection.length > 0 || flexibleSpaceIntersection.length > 0 else {
            layoutManager.setGlyphs(glyphs, properties: props, characterIndexes: charIndexes,
                                    font: aFont, forGlyphRange: glyphRange)
            return glyphRange.length
        }
        
        // Create a mutable pointer for the glyph and property array.
        // Note that “glyphs” and “characterIndexes” that pass in to this method are always one-to-one.
        // For example, if glyph 0 and 1 both map to character 0, then characterIndexes[0] and characterIndexes[1] are both 0.
        //
        let finalGlyphs = UnsafeMutablePointer<CGGlyph>(mutating: glyphs)
        let finalProps = UnsafeMutablePointer<NSLayoutManager.GlyphProperty>(mutating: props)

        // Generate the ellipsis glyph using aFont.
        //
        let myCharacter: [UniChar] = [0x2026] // Ellipsis: U+0x2026
        var myGlyphs: [CGGlyph] = [0]
        let canEncode = CTFontGetGlyphsForCharacters(aFont, myCharacter, &myGlyphs, myCharacter.count)
        if !canEncode {
            print("! Failed to get the glyphs for characters \(myCharacter).")
        }
        
        // Replace the first glyph with an ellipsis and ignore the others.
        // Set the property of the flexible space glyphs to .controlCharacter.
        //
        let ellipsisStartIndex = ellipsisIntersection.location
        for index in ellipsisStartIndex..<ellipsisStartIndex + ellipsisIntersection.length {
            if index == ellipsisGlyphRange!.location {
                finalGlyphs[index - glyphRange.location] = myGlyphs[0]
            } else {
                finalProps[index - glyphRange.location] = .controlCharacter
            }
        }
        let flexibleSpaceStartIndex = flexibleSpaceIntersection.location
        for index in  flexibleSpaceStartIndex..<flexibleSpaceStartIndex + flexibleSpaceIntersection.length {
            finalProps[index - glyphRange.location] = .controlCharacter
        }

        // Set glyphs and return the length.
        //
        layoutManager.setGlyphs(finalGlyphs, properties: finalProps, characterIndexes: charIndexes,
                                font: aFont, forGlyphRange: glyphRange)
        return glyphRange.length
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager,
                       shouldSetLineFragmentRect lineFragmentRect: UnsafeMutablePointer<CGRect>,
                       lineFragmentUsedRect: UnsafeMutablePointer<CGRect>,
                       baselineOffset: UnsafeMutablePointer<CGFloat>,
                       in textContainer: NSTextContainer,
                       forGlyphRange glyphRange: NSRange) -> Bool {
        guard let ellipsisGlyphRange = self.ellipsisGlyphRange,
            glyphRange.location > ellipsisGlyphRange.location else {
                return false
        }
        let originX = textContainer.size.width
        lineFragmentRect.pointee.origin = CGPoint(x: originX, y: lineFragmentRect.pointee.origin.y)
        return true
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager, shouldUse action: NSLayoutManager.ControlCharacterAction,
                       forControlCharacterAt charIndex: Int) -> NSLayoutManager.ControlCharacterAction {
        if let flexibleSpaceGlyphRange = self.flexibleSpaceGlyphRange,
            flexibleSpaceGlyphRange.contains(layoutManager.glyphIndexForCharacter(at: charIndex)) {
            return .whitespace
        }
        return action
    }
    
    func layoutManager(_ layoutManager: NSLayoutManager,
                       boundingBoxForControlGlyphAt glyphIndex: Int,
                       for textContainer: NSTextContainer,
                       proposedLineFragment proposedRect: CGRect,
                       glyphPosition: CGPoint,
                       characterIndex charIndex: Int) -> CGRect {
        guard let flexibleSpaceGlyphRange = self.flexibleSpaceGlyphRange,
            flexibleSpaceGlyphRange.contains(glyphIndex) else {
            return CGRect(x: glyphPosition.x, y: glyphPosition.y, width: 0, height: proposedRect.height)
        }
        let padding = textContainer.lineFragmentPadding * 2
        let width = proposedRect.width - (glyphPosition.x - proposedRect.minX) - padding
        let rect = CGRect(x: glyphPosition.x, y: glyphPosition.y, width: width, height: proposedRect.height)
        return rect
    }
}
