extension BlockInputBlockItem {
    func applySlashCommandConfiguration(
        rawSlashCommandChips: Bool,
        rawFileMentionChips: Bool,
        selectAllBehavior: BlockInputSelectAllBehavior,
        slashCommandAvailability: BlockInputSlashCommandAvailability,
        isDocumentStartBlock: Bool
    ) {
        self.rawSlashCommandChips = rawSlashCommandChips
        self.rawFileMentionChips = rawFileMentionChips
        self.selectAllBehavior = selectAllBehavior
        self.slashCommandAvailability = slashCommandAvailability
        self.isDocumentStartBlock = isDocumentStartBlock
    }
}
