require "test_helper"

class CharactersControllerTest < ActionDispatch::IntegrationTest
  setup do
    @character = characters(:one)
  end

  test "should get index" do
    get characters_url
    assert_response :success
  end

  test "should get new" do
    get new_character_url
    assert_response :success
  end

  test "should create character" do
    assert_difference("Character.count") do
      post characters_url, params: { character: { adult: @character.adult, description: @character.description, external_created_at: @character.external_created_at, external_updated_at: @character.external_updated_at, name: @character.name, share_url: @character.share_url, slug: @character.slug, stats: @character.stats, web_enabled: @character.web_enabled } }
    end

    assert_redirected_to character_url(Character.last)
  end

  test "should show character" do
    get character_url(@character)
    assert_response :success
  end

  test "should get edit" do
    get edit_character_url(@character)
    assert_response :success
  end

  test "should update character" do
    patch character_url(@character), params: { character: { adult: @character.adult, description: @character.description, external_created_at: @character.external_created_at, external_updated_at: @character.external_updated_at, name: @character.name, share_url: @character.share_url, slug: @character.slug, stats: @character.stats, web_enabled: @character.web_enabled } }
    assert_redirected_to character_url(@character)
  end

  test "should destroy character" do
    assert_difference("Character.count", -1) do
      delete character_url(@character)
    end

    assert_redirected_to characters_url
  end
end
