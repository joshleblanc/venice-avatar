require "application_system_test_case"

class CharactersTest < ApplicationSystemTestCase
  setup do
    @character = characters(:one)
  end

  test "visiting the index" do
    visit characters_url
    assert_selector "h1", text: "Characters"
  end

  test "should create character" do
    visit characters_url
    click_on "New character"

    check "Adult" if @character.adult
    fill_in "Description", with: @character.description
    fill_in "External created at", with: @character.external_created_at
    fill_in "External updated at", with: @character.external_updated_at
    fill_in "Name", with: @character.name
    fill_in "Share url", with: @character.share_url
    fill_in "Slug", with: @character.slug
    fill_in "Stats", with: @character.stats
    check "Web enabled" if @character.web_enabled
    click_on "Create Character"

    assert_text "Character was successfully created"
    click_on "Back"
  end

  test "should update Character" do
    visit character_url(@character)
    click_on "Edit this character", match: :first

    check "Adult" if @character.adult
    fill_in "Description", with: @character.description
    fill_in "External created at", with: @character.external_created_at.to_s
    fill_in "External updated at", with: @character.external_updated_at.to_s
    fill_in "Name", with: @character.name
    fill_in "Share url", with: @character.share_url
    fill_in "Slug", with: @character.slug
    fill_in "Stats", with: @character.stats
    check "Web enabled" if @character.web_enabled
    click_on "Update Character"

    assert_text "Character was successfully updated"
    click_on "Back"
  end

  test "should destroy Character" do
    visit character_url(@character)
    click_on "Destroy this character", match: :first

    assert_text "Character was successfully destroyed"
  end
end
