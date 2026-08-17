import SwiftUI

/// A recording that has been sent but hasn't landed in Supabase yet.
///
/// It carries its placeholder date title, because the real one is generated from
/// the transcript after the save. Shown for the same reason the import rows are:
/// work the user just started should be visible where its result will be, not
/// only once the round trip finishes.
struct PendingRecordingRow: View {
    let upload: RecordingManager.PendingUpload

    var body: some View {
        AppCard {
            HStack {
                AppChip(text: upload.isWaiting ? "Waiting" : "Saving")
                Spacer()
                Text(upload.createdAt, format: .dateTime.day().month(.abbreviated).year())
                    .appTextStyle(.mono)
                    .foregroundStyle(AppColors.neutral500)
            }
            Text(upload.title)
                .appTextStyle(.bodyMedium)
                .foregroundStyle(AppColors.neutral800)

            Text(upload.isWaiting
                 ? "Saved on this phone. It uploads as soon as you’re back online."
                 : "Saving to your library…")
                .appTextStyle(.small)
                .foregroundStyle(AppColors.neutral500)
        }
    }
}
