require 'rails_helper'

describe "Users API" do

  before(:each) do
    ActionMailer::Base.deliveries = []
  end

  context 'GET /user' do
    let(:token) { authenticate(email: "josh@example.com", password: "password") }

    before do
      create(:user, email: "josh@example.com", username: "joshsmith", password: "password")
    end

    context 'when authenticated' do
      it 'returns the authenticated user object' do
        authenticated_get "user", {}, token

        expect(last_response.status).to eq 200

        user_attributes = json.data.attributes

        expect(user_attributes.email).to eq "josh@example.com"
        expect(user_attributes.username).to eq "joshsmith"
        expect(user_attributes.password).to be_nil
      end
    end

    context 'when unauthenticated' do
      it 'returns a 401 unauthorized' do
        get "#{host}/user"

        expect(last_response.status).to eq 401

        expect(json).to be_a_valid_json_api_error.with_id "NOT_AUTHORIZED"
      end
    end
  end

  context 'GET /users/:id' do
    before do
      @user = create(:user, username: "joshsmith")
      create_list(:user_skill, 10, user: @user)
      get "#{host}/users/#{@user.id}"
    end

    it "responds with a 200" do
      expect(last_response.status).to eq 200
    end

    it "retrieves the specified user by id using UserSerializer, including skills" do
      expect(json).to serialize_object(User.find(@user.id)).with(UserSerializer).with_includes("skills")
      expect(json.data.id).to eq @user.id.to_s
    end
  end

  context 'GET /users' do
    before do
      @user = create(:user, email: "josh@example.com", username: "joshsmith", password: "password")
    end

    it 'returns a user object if the user exists' do
      get "#{host}/users/#{@user.id}",{}

      expect(last_response.status).to eq 200

      user_attributes = json.data.attributes

      expect(user_attributes.email).to eq "josh@example.com"
      expect(user_attributes.username).to eq "joshsmith"
      expect(user_attributes.password).to be_nil
    end
  end

  context 'POST /users' do

    context "when registering through Facebook" do
      before do
        oauth = Koala::Facebook::OAuth.new(ENV["FACEBOOK_APP_ID"], ENV["FACEBOOK_APP_SECRET"], ENV["FACEBOOK_REDIRECT_URL"])
        test_users = Koala::Facebook::TestUsers.new(app_id: ENV["FACEBOOK_APP_ID"], secret: ENV["FACEBOOK_APP_SECRET"])
        facebook_user = test_users.create(true, "email,user_friends")

        short_lived_token = facebook_user["access_token"]
        long_lived_token_info = oauth.exchange_access_token_info(short_lived_token)
        facebook_auth_code = oauth.generate_client_code(long_lived_token_info["access_token"])
        access_token_info = oauth.get_access_token_info(facebook_auth_code)

        @facebook_access_token = access_token_info["access_token"] || JSON.parse(access_token_info.keys[0])["access_token"]
        @facebook_id = facebook_user["id"]
      end

      context "when parameters are valid" do
        before do
          params = {
            email: "josh@example.com",
            username: "joshsmith",
            password: "password",
            facebook_id: @facebook_id,
            facebook_access_token: @facebook_access_token
          }
          json_api_params = json_api_params_for("users", params)
          post "#{host}/users", json_api_params
        end

        it "creates a valid user", vcr: { cassette_name: "requests/api/users/valid_facebook_request" } do
          expect(User.last.email).to eq "josh@example.com"
          expect(User.last.username).to eq "joshsmith"
          expect(User.last.facebook_id).to eq @facebook_id
          expect(User.last.facebook_access_token).to eq @facebook_access_token
        end

        it "responds with a 200", vcr: { cassette_name: "requests/api/users/valid_facebook_request" } do
          expect(last_response.status).to eq 200
        end

        it "returns the created user using UserSerializer", vcr: { cassette_name: "requests/api/users/valid_facebook_request" } do
          expect(json).to serialize_object(User.last).with(UserSerializer).with_includes("skills")
        end

      end

    end

    context "when registering directly" do

      it 'creates a valid user' do
        params = { email: "josh@example.com", username: "joshsmith", password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 200

        user_attributes = json.data.attributes

        expect(user_attributes.email).to eq "josh@example.com"
        expect(user_attributes.username).to eq "joshsmith"
        expect(user_attributes.password).to be_nil
      end
    end

    context 'with invalid data' do

      it 'fails when an organization has a slug matching the username' do
        create(:organization, name: "Code Corps")

        params = { email: "josh@example.com", username: "code-corps", password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422

        expect(json.errors[0].detail).to eq "Username has already been taken by an organization"
      end

      it 'fails on a blank password and username' do
        params = { email: "josh@example.com", username: "", password: "" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422

        expect(json.errors[0].detail).to eq "Password can't be blank"
        expect(json.errors[1].detail).to eq "Username can't be blank"
      end

      it 'fails on a too long username' do
        params = { email: "josh@example.com", username: "A" * 40, password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422

        expect(json.errors[0].detail).to eq "Username is too long (maximum is 39 characters)"
      end

      it 'fails on a username with invalid characters' do
        params = { email: "josh@example.com", username: "this-won't-work", password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422

        expect(json.errors[0].detail).to eq "Username may only contain alphanumeric characters, underscores, or single hyphens, and cannot begin or end with a hyphen or underscore"
      end
    end

    context 'when user accounts are taken' do
      before do
        create(:user, email: "josh@example.com", username: "joshsmith", password: "password")
      end

      it 'fails when the email is taken' do
        params = { email: "josh@example.com", username: "joshsmith", password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422

        expect(json.errors[0].detail).to eq "Email has already been taken"
      end

      it 'fails when the username is taken' do
        params = { email: "newemail@gmail.com", username: "joshsmith", password: "password" }
        json_api_params = json_api_params_for("users", params)

        post "#{host}/users", json_api_params

        expect(last_response.status).to eq 422
        expect(json.errors[0].detail).to eq "Username has already been taken"
      end
    end
  end

  context "POST /users/forgot_password" do

    before do
      @user = create(:user, id: 10, email: 'existing-user@mail.com', password: 'test_password')
    end

    it "returns the user when the email is found" do
      json_api_params = json_api_params_for("users", {email: "existing-user@mail.com"})
      post "#{host}/users/forgot_password", json_api_params

      expect(last_response.status).to eq 200

      user_attributes = json.data.attributes
      expect(user_attributes.email).to eq @user.email
    end

    it "returns an error when the email is not found" do
      json_api_params = json_api_params_for("users", {email: "not-existing-user@mail.com"})
      post "#{host}/users/forgot_password", json_api_params

      expect(last_response.status).to eq 422
      expect(json).to be_a_valid_json_api_error.with_id "VALIDATION_ERROR"
      expect(json).to contain_an_error_of_type("VALIDATION_ERROR").with_message "Email doesn't exist in the database"
    end
  end

  context "POST /users/reset_password" do

    before do
      @user = create(:user, id: 10, email: 'existing-user@mail.com', password: 'test_password')
    end

    it "resets the password when the authentication token is valid" do
      json_api_params = json_api_params_for("users", {email: "existing-user@mail.com"})
      post "#{host}/users/forgot_password", json_api_params

      user = User.first

      json_api_params = json_api_params_for("users", {
        confirmation_token: "#{user.confirmation_token}",
        password: "newpassword"
      })
      post "#{host}/users/reset_password", json_api_params

      expect(last_response.status).to eq 200
      token = authenticate(email: "existing-user@mail.com", password: "newpassword")
      expect(token).to_not be_nil
    end

    it "doesn't reset the password when the authentication token is not valid" do
      json_api_params = json_api_params_for("users", {email: "existing-user@mail.com"})
      post "#{host}/users/forgot_password", json_api_params

      user = User.first

      json_api_params = json_api_params_for("users", {
        confirmation_token: "fakeconfirmationtoken",
        password: "newpassword"
        })
      post "#{host}/users/reset_password", json_api_params

      expect(last_response.status).to eq 422
      expect(json).to be_a_valid_json_api_error.with_id "VALIDATION_ERROR"
      expect(json).to contain_an_error_of_type("VALIDATION_ERROR").with_message "Password couldn't be reset"
    end
  end

  context "PATCH /users/:id" do
    before do
      @edited_user = create(:user, id: 1, website: "initial.com", biography: "Initial", twitter: "@user")
      params = {
        website: "edit.com", biography: "Edited", twitter: "@edit",
        email: "new@mail.com", encrypted_password: "bla", confirmation_token: "bla",
        remember_token: "bla", username: "bla", admin: true
      }
      @edit_params = json_api_params_for("users", params)
    end

    context "when unauthenticated" do
      it "returns a 401 with a proper error message" do
        patch "#{host}/users/1", @edit_params

        expect(last_response.status).to eq 401
        expect(json).to be_a_valid_json_api_error.with_id("NOT_AUTHORIZED")
      end
    end

    context "when authenticated" do
      context "as an admin" do
        before do
          @admin = create(:user, admin: true, email: "admin@mail.com", password: "password")
          @token = authenticate(email: "admin@mail.com", password: "password")
        end

        it "performs the edit" do
          params = {
            data: {
              type: "users",
              attributes: { website: "edit.com", biography: "Edited", twitter: "@edit" }
            }
          }

          authenticated_patch "/users/1", params, @token

          expect(last_response.status).to eq 200

          user_json = json.data.attributes
          expect(user_json.website).to eq "edit.com"
          expect(user_json.biography).to eq "Edited"
          expect(user_json.twitter).to eq "@edit"

          user = @edited_user.reload
          expect(user.website).to eq "edit.com"
          expect(user.biography).to eq "Edited"
          expect(user.twitter).to eq "@edit"
        end

        it "allows updating of only specific parameters" do
          expect_any_instance_of(User).to receive(:assign_attributes).with({ website: "edit.com", biography: "Edited", twitter: "@edit"}.with_indifferent_access)
          authenticated_patch "/users/1", @edit_params, @token
        end

        it "renders validation errors if parameter values are invalid" do
          invalid_params = json_api_params_for("users", {website: "multi word"})
          authenticated_patch "/users/1", invalid_params, @token
          expect(last_response.status).to eq 422
          expect(json).to be_a_valid_json_api_error.with_id "VALIDATION_ERROR"
        end
      end

      context "as another user" do
        before do
          @regular_user = create(:user, admin: false, email: "regular@mail.com", password: "password")
          @token = authenticate(email: "regular@mail.com", password: "password")
        end

        it "returns a 401 with a proper error message" do
          authenticated_patch "/users/1", @edit_params, @token

          expect(last_response.status).to eq 401
          expect(json).to be_a_valid_json_api_error.with_id("ACCESS_DENIED")
        end
      end
    end
  end

  context "PATCH /users/me" do

    before do
      @current_user = create(:user, email: "current@mail.com", password: "password", website: "initial.com", biography: "Initial", twitter: "@user")
      params = {
        website: "edit.com", biography: "Edited", twitter: "@edit",
        email: "new@mail.com", encrypted_password: "bla", confirmation_token: "bla",
        remember_token: "bla", username: "bla", admin: true
      }
      @edit_params = json_api_params_for("users", params)
    end

    context "when unauthenticated" do
      it "returns a 401 with a proper error message" do
        patch "#{host}/users/me", @edit_params

        expect(last_response.status).to eq 401
        expect(json).to be_a_valid_json_api_error.with_id("NOT_AUTHORIZED")
      end
    end

    context "when authenticated" do
      before do
        @token = authenticate(email: "current@mail.com", password: "password")
      end

      it "performs the edit" do
        authenticated_patch "/users/me", @edit_params, @token

        expect(last_response.status).to eq 200

        user_json = json.data.attributes
        expect(user_json.website).to eq "edit.com"
        expect(user_json.biography).to eq "Edited"
        expect(user_json.twitter).to eq "@edit"

        current_user = @current_user.reload
        expect(current_user.website).to eq "edit.com"
        expect(current_user.biography).to eq "Edited"
        expect(current_user.twitter).to eq "@edit"
      end

      it "allows updating of only specific parameters" do
        expect_any_instance_of(User).to receive(:assign_attributes).with({ website: "edit.com", biography: "Edited", twitter: "@edit"}.with_indifferent_access)
        authenticated_patch "/users/me", @edit_params, @token
      end

      it "renders validation errors if parameter values are invalid" do
        invalid_params = json_api_params_for("users", {website: "multi word"})
        authenticated_patch "/users/me", invalid_params, @token
        expect(last_response.status).to eq 422
        expect(json).to be_a_valid_json_api_error.with_id "VALIDATION_ERROR"
      end
    end
  end
end
