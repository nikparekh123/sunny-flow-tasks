//
//  SunnyPageHead.swift
//  Sunny — the note a page shows when it has nothing else to say. The name
//  page heading and figures that lived here were deleted (8 Oct 2026).
//

import SwiftUI

// MARK: - an honest empty page

/// 15px at weight 300, which clears the 14px floor by one step. A page with no
/// card says so in a sentence rather than showing a blank column.
struct SunnyPageNote: View {
    let text: String
    init(_ t: String) { text = t }

    var body: some View {
        Text(text)
            .font(S.inter(S.tDigestBody, S.wLightN))
            .lineSpacing(S.tDigestBody * (S.lhDigest - 1))
            .foregroundStyle(S.shellEmptyInk)
            .frame(width: S.content, alignment: .leading)
            .padding(.top, S.gap1)
            .padding(.bottom, S.gap3)
    }
}
