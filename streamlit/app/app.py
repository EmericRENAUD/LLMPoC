import os

import streamlit as st
from openai import OpenAI

VLLM_BASE_URL = os.getenv("VLLM_BASE_URL", "http://vllm-server:8000/v1")
VLLM_API_KEY = os.getenv("VLLM_API_KEY", "EMPTY")
MODEL_NAME = os.getenv("MODEL_NAME", "meta-llama/Llama-3.2-1B-Instruct")

st.set_page_config(page_title="Chat LLM", page_icon="💬")
st.title("💬 Chat LLM")

client = OpenAI(base_url=VLLM_BASE_URL, api_key=VLLM_API_KEY)

with st.sidebar:
    st.header("Paramètres")
    system_prompt = st.text_area(
        "Prompt système", "Tu es un assistant utile. Réponds en français.", height=120
    )
    temperature = st.slider("Température", 0.0, 2.0, 0.7, 0.05)
    max_tokens = st.slider("Tokens max", 64, 4096, 1024, 64)
    if st.button("Nouvelle conversation"):
        st.session_state.messages = []
        st.rerun()

if "messages" not in st.session_state:
    st.session_state.messages = []

for msg in st.session_state.messages:
    with st.chat_message(msg["role"]):
        st.markdown(msg["content"])

if prompt := st.chat_input("Votre message"):
    st.session_state.messages.append({"role": "user", "content": prompt})
    with st.chat_message("user"):
        st.markdown(prompt)

    with st.chat_message("assistant"):
        try:
            stream = client.chat.completions.create(
                model=MODEL_NAME,
                messages=[{"role": "system", "content": system_prompt}]
                + st.session_state.messages,
                temperature=temperature,
                max_tokens=max_tokens,
                stream=True,
            )
            answer = st.write_stream(
                chunk.choices[0].delta.content or ""
                for chunk in stream
                if chunk.choices
            )
        except Exception as e:
            answer = f"Erreur lors de l'appel au LLM : {e}"
            st.error(answer)

    st.session_state.messages.append({"role": "assistant", "content": answer})
