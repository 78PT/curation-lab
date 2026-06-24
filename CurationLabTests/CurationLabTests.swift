import XCTest
@testable import CurationLab

final class CurationLabTests: XCTestCase {
    
    func testLLMAnalysisRecordCodable() throws {
        let record = LLMAnalysisRecord(tags: ["sunny", "beach", "happy"], description: "A great day at the beach.")
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(record)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(LLMAnalysisRecord.self, from: data)
        
        XCTAssertEqual(decoded.tags, ["sunny", "beach", "happy"])
        XCTAssertEqual(decoded.description, "A great day at the beach.")
    }
    
    func testPhotoAlbumCreation() {
        let album = PhotoAlbum(localIdentifier: "test-id", title: "Vacation", count: 12, isShared: true)
        
        XCTAssertEqual(album.localIdentifier, "test-id")
        XCTAssertEqual(album.title, "Vacation")
        XCTAssertEqual(album.count, 12)
        XCTAssertTrue(album.isShared)
    }
    
    func testMemoryJSONParsing() {
        let jsonString = """
        {
          "selected_photo_ids": ["id1", "id2"],
          "headline": "Beach trip",
          "story": "We had fun in the sun."
        }
        """
        
        guard let data = jsonString.data(using: .utf8) else {
            XCTFail("Failed to convert string to data")
            return
        }
        
        let decoded = try? JSONDecoder().decode(CuratedMemory.self, from: data)
        XCTAssertNotNil(decoded)
        XCTAssertEqual(decoded?.selected_photo_ids, ["id1", "id2"])
        XCTAssertEqual(decoded?.headline, "Beach trip")
        XCTAssertEqual(decoded?.story, "We had fun in the sun.")
    }
    
    func testSavedMemoryCodable() throws {
        let saved = SavedMemory(
            idString: "saved-id",
            headline: "Headline",
            story: "Story text",
            photoIds: ["p1", "p2"],
            dateCreated: Date(),
            isSlideshow: true
        )
        
        let encoder = JSONEncoder()
        let data = try encoder.encode(saved)
        
        let decoder = JSONDecoder()
        let decoded = try decoder.decode(SavedMemory.self, from: data)
        
        XCTAssertEqual(decoded.idString, "saved-id")
        XCTAssertEqual(decoded.headline, "Headline")
        XCTAssertEqual(decoded.story, "Story text")
        XCTAssertEqual(decoded.photoIds, ["p1", "p2"])
        XCTAssertEqual(decoded.isSlideshow, true)
    }
}
