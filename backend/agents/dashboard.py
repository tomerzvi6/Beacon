import streamlit as st

st.set_page_config(page_title="Beacon Control Room", layout="wide")
st.title("Beacon — Control Room")
st.caption("HITL approval dashboard for the Operational AI Team")

tab_inbox, tab_activity, tab_metrics, tab_health = st.tabs(
    ["Inbox", "Activity", "Metrics", "Health"]
)

with tab_inbox:
    st.info("No drafts awaiting approval.")

with tab_activity:
    st.info("No agent runs yet.")

with tab_metrics:
    st.info("No weekly snapshots yet.")

with tab_health:
    st.success("Scheduler: not started")
