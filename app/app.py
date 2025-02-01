import streamlit as st
import os


st.set_page_config(
    page_title="Login and download",
    page_icon="👋",
)


st.title("Login and upload file")



microsoft_login = st.button("Microsoft Entra login")

if microsoft_login:
    st.login(provider="microsoft")


logout_button = st.button("Logout")

if logout_button:
    st.logout()


user_data = st.experimental_user # This provides the information about the logged in user


# Check if user data exists and get the name
if user_data and user_data.get("is_logged_in", False):
    if "name" in user_data and user_data["name"]:
        st.write(f"User name: {user_data['name']}")
    if "email" in user_data and user_data["email"]:
        st.write(f"Email: {user_data['email']}")
    if "preferred_username" in user_data and user_data["preferred_username"]:
        st.write(f"Prefered Username: {user_data['preferred_username']}")

    # Allow file upload
    st.write("You are logged in, you can upload files.")
    uploaded_file = st.file_uploader("Choose a file")
    
    if uploaded_file is not None:
        file_extension = os.path.splitext(uploaded_file.name)[1].lower()
        if file_extension in ['.txt', '.pdf', '.jpg','.csv']:  # Validate file type
            content = uploaded_file.read()

            # Add file size limit check
            if len(content) > 200 * 1024 * 1024:  # 10 MB limit
                st.write("File too large!")
            else:
                st.write(f"Uploaded file content: {content}")
        else:
            st.write("Unsupported file type! Only .txt, .pdf, and .jpg files are allowed.")

    
else:
    st.write("No user data available")
    st.write("Please log in to upload files.")


